import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import axios from 'axios';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

admin.initializeApp();

export const onTikTokLinkAdded = functions.runWith({
    timeoutSeconds: 540,
    memory: '1GB',
    secrets: ["GEMINI_API_KEY", "MAPS_API_KEY"]
}).firestore.document("tiktok_links/{docId}").onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    const tiktokUrl = data?.url;
    const tempFilePath = path.join(os.tmpdir(), `video_${context.params.docId}.mp4`);

    const GEMINI_KEY = process.env.GEMINI_API_KEY;
    const MAPS_KEY = process.env.MAPS_API_KEY;

    try {
        // --- שלב 1: שליפת מטא-דאטה והורדת הוידאו ---
        const tikRes = await axios.post('https://www.tikwm.com/api/', { url: tiktokUrl });
        if (!tikRes.data.data) throw new Error("Could not fetch TikTok data");

        const videoId = tikRes.data.data.id;
        const directVideoUrl = tikRes.data.data.play;

        const videoResponse = await axios({ url: directVideoUrl, method: 'get', responseType: 'stream' });
        const writer = fs.createWriteStream(tempFilePath);
        videoResponse.data.pipe(writer);

        await new Promise<void>((resolve, reject) => {
            writer.on('finish', resolve);
            writer.on('error', reject);
        });

        // --- שלב 2: שליפת תגובות גולשים (תיקון: הוספת URL) ---
        let commentsText = "No comments available.";
        try {
            // ה-API דורש גם את ה-ID וגם את ה-URL המלא כדי לאשר את הבקשה
            const commentsUrl = `https://www.tikwm.com/api/comment/list?id=${videoId}&url=${encodeURIComponent(tiktokUrl)}`;
            const commentsRes = await axios.get(commentsUrl);

            console.log("Debug TikWM Response:", JSON.stringify(commentsRes.data));

            // שליפת רשימת התגובות מהמבנה של TikWM
            const commentsList = commentsRes.data.data?.comments || [];

            if (commentsList && commentsList.length > 0) {
                commentsText = commentsList
                    .slice(0, 20)
                    .map((c: any) => c.text)
                    .join(" | ");
                console.log(`Successfully fetched ${commentsList.length} comments.`);
            } else {
                console.log("Comments list is empty or API returned error:", commentsRes.data.msg);
            }
        } catch (e: any) {
            console.error("Comments API Error:", e.message);
        }

        // --- שלב 3: ניתוח משולב ב-Gemini AI ---
        const videoBase64 = fs.readFileSync(tempFilePath).toString("base64");
        const geminiUrl = `https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=${GEMINI_KEY}`;

        const payload = {
            contents: [{
                parts: [
                    { text: `Analyze this video and these user comments: "${commentsText}".
                             Extract restaurant details in ENGLISH.

                             STRICT RULES FOR CONTENT:
                             - "name": Official restaurant name.
                             - "address": Real physical address.
                             - "cuisine": Primary food type (1-2 words).
                             - "recommendation_essence": A rich 1-sentence description. Must include the vibe and a key feature. (Example: "A lively rooftop bar serving creative cocktails and Japanese-fusion small plates").
                             - "community_sentiment": A detailed but brief summary of what people say. (Example: "Mixed reviews: many praise the unique flavors, but several users mention long wait times and high prices").
                             - "sentiment_score": "positive", "neutral", or "negative".
                             - "must_order_dishes": Array of 1-3 specific dishes.
                             - "price_level": "expensive", "normal", "cheap", or "not-known".
                             - "recommendation_tags": Array of 3-5 tags.
                             - "website": Official URL.

                             Return ONLY valid JSON.`
                    },
                    { inline_data: { mime_type: "video/mp4", data: videoBase64 } }
                ]
            }]
        };

        const geminiRes = await axios.post(geminiUrl, payload);
        const responseText = geminiRes.data.candidates[0].content.parts[0].text;
        const aiData = JSON.parse(responseText.replace(/```json|```/g, "").trim());

        // --- שלב 4: Geocoding לאימות כתובת ומיקום ---
        const searchQuery = `${aiData.name} ${aiData.address}`;
        const geoRes = await axios.get(`https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(searchQuery)}&key=${MAPS_KEY}`);

        const firstResult = geoRes.data.results[0];

        // כאן קורה הקסם: אם גוגל מצא תוצאה, אנחנו לוקחים את הכתובת הרשמית שלו (Formatted Address)
        // זה מנקה סופית הערות כמו "20 דקות מתל אביב" והופך אותן לכתובת סטנדרטית
        const finalAddress = firstResult ? firstResult.formatted_address : aiData.address;
        const loc = firstResult?.geometry.location || { lat: 32.0853, lng: 34.7818 };

        // --- שלב 5: שמירת הנתונים ---
        await admin.firestore().collection("restaurants").add({
            ...aiData,
            address: finalAddress, // הכתובת המנוקה והרשמית
            location: { lat: loc.lat, lng: loc.lng },
            videoUrl: tiktokUrl,
            sourceCommentsUsed: commentsText !== "No comments available.",
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // ניקוי קובץ זמני ועדכון סטטוס
        if (fs.existsSync(tempFilePath)) fs.unlinkSync(tempFilePath);
        return snapshot.ref.update({ status: "completed" });

    } catch (error: any) {
        if (fs.existsSync(tempFilePath)) fs.unlinkSync(tempFilePath);
        console.error("Error in AI analysis flow:", error.message);
        return snapshot.ref.update({ status: "error", message: error.message });
    }
});