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
        // שלב 1 ו-2: הורדת הוידאו (ללא שינוי)
        const tikRes = await axios.post('https://www.tikwm.com/api/', { url: tiktokUrl });
        const directVideoUrl = tikRes.data.data.play;

        const videoResponse = await axios({ url: directVideoUrl, method: 'get', responseType: 'stream' });
        const writer = fs.createWriteStream(tempFilePath);
        videoResponse.data.pipe(writer);
        await new Promise<void>((resolve, reject) => {
            writer.on('finish', () => resolve());
            writer.on('error', reject);
        });

        // שלב 3: ה-Prompt המורחב ל-Gemini (כאן קורה הקסם)
        const videoBase64 = fs.readFileSync(tempFilePath).toString("base64");
        const geminiUrl = `https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=${GEMINI_KEY}`;

        const payload = {
    contents: [{
        parts: [
            { text: `Analyze this video and extract restaurant details in ENGLISH.
                     Return ONLY a JSON object with these fields:
                     1. "name": Restaurant name.
                     2. "address": Full address.
                     3. "cuisine": Type of food.
                     4. "recommendation_essence": Short summary.
                     5. "recommendation_tags": Array of tags (e.g., ["Cheap", "Romantic"]).
                     6. "website": The official website URL of the restaurant (find it based on the name).`
            },
            { inline_data: { mime_type: "video/mp4", data: videoBase64 } }
        ]
    }]
};

        const geminiRes = await axios.post(geminiUrl, payload);
        const responseText = geminiRes.data.candidates[0].content.parts[0].text;
        const aiData = JSON.parse(responseText.replace(/```json|```/g, "").trim());

        // שלב 4: Geocoding (שימוש בשם + כתובת לדיוק מקסימלי)
        const searchQuery = `${aiData.name} ${aiData.address}`;
        const geoRes = await axios.get(`https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(searchQuery)}&key=${MAPS_KEY}`);
        const loc = geoRes.data.results[0]?.geometry.location || { lat: 32.0853, lng: 34.7818 };

        // שלב 5: שמירת כל הנתונים המורחבים ל-Firestore
        await admin.firestore().collection("restaurants").add({
            ...aiData, // מכניס את name, address, cuisine, recommendation_essence, recommendation_tags
            location: { lat: loc.lat, lng: loc.lng },
            videoUrl: tiktokUrl, // הקישור למסעדה/סרטון כפי שביקשת
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        if (fs.existsSync(tempFilePath)) fs.unlinkSync(tempFilePath);
        return snapshot.ref.update({ status: "completed" });

    } catch (error: any) {
        if (fs.existsSync(tempFilePath)) fs.unlinkSync(tempFilePath);
        console.error("Error in expanded flow:", error.message);
        return snapshot.ref.update({ status: "error", message: error.message });
    }
});