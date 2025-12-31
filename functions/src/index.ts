import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import axios from 'axios';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

admin.initializeApp();

const IG_HOST = "social-media-video-downloader.p.rapidapi.com";

// פונקציית עזר לחילוץ הלינק לתמונה מתוך ה-JSON של טיקטוק
async function fetchThumbnailUrl(videoUrl: string): Promise<string> {
    try {
        if (videoUrl.includes('tiktok.com')) {
            const res = await axios.get(`https://www.tiktok.com/oembed?url=${videoUrl}`);
            return res.data?.thumbnail_url || "";
        }
        if (videoUrl.includes('instagram.com')) {
            return `${videoUrl.split('?')[0]}media/?size=l`;
        }
    } catch (e) {
        console.error("Thumbnail fetch failed", e);
    }
    return "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800";
}

export const onTikTokLinkAdded = functions.runWith({
    timeoutSeconds: 540,
    memory: '1GB',
    secrets: ["GEMINI_API_KEY", "MAPS_API_KEY", "RAPID_API_KEY"]
}).firestore.document("tiktok_links/{docId}").onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    const rawUrl = data?.url || "";
    const userId = data?.userId || "anonymous";
    const tempFilePath = path.join(os.tmpdir(), `video_${context.params.docId}.mp4`);

    const GEMINI_KEY = process.env.GEMINI_API_KEY;
    const MAPS_KEY = process.env.MAPS_API_KEY;
    const RAPID_KEY = process.env.RAPID_API_KEY;

    try {
        console.log(`[START] Processing URL: ${rawUrl}`);
        const restaurantsRef = admin.firestore().collection("restaurants");

        // --- שלב הגנה מוקדם: האם הלינק כבר קיים אצל המשתמש באחת המסעדות? ---
        const existingLinkQuery = await restaurantsRef
            .where('userId', '==', userId)
            .where('videoUrls', 'array-contains', rawUrl)
            .get();

        if (!existingLinkQuery.empty) {
            console.log(`[SKIP] Video URL ${rawUrl} already processed for this user.`);
            return snapshot.ref.update({ status: "completed", message: "Link already exists" });
        }

        let directVideoUrl = "";
        let videoDescription = "No caption found";
        let authorName = "Social Creator";
        let commentsText = "No comments available";

        // --- שלב 1: חילוץ נתונים (TikTok/Instagram) ---
        let source = "tiktok";
        if (rawUrl.includes("instagram.com")) {
            source = "instagram";
            const urlParts = rawUrl.split("/");
            const reelIndex = urlParts.findIndex((part: string) => part === "reel" || part === "p" || part === "reels");
            const shortcode = reelIndex !== -1 ? urlParts[reelIndex + 1] : "";

            const videoRes = await axios.get(`https://${IG_HOST}/instagram/v3/media/post/details`, {
                params: { shortcode: shortcode, renderableFormats: 'all' },
                headers: { "x-rapidapi-key": RAPID_KEY || "", "x-rapidapi-host": IG_HOST }
            });

            const contents = videoRes.data?.contents?.[0];
            directVideoUrl = contents?.videos?.[0]?.url || videoRes.data?.video_url;
            videoDescription = contents?.description || videoRes.data?.caption?.text || "No caption found";

            try {
                const infoRes = await axios.get(`https://${IG_HOST}/instagram/v1/media/details`, {
                    params: { url_or_shortcode: shortcode },
                    headers: { "x-rapidapi-key": RAPID_KEY || "", "x-rapidapi-host": IG_HOST }
                });
                const mediaData = infoRes.data?.data;
                if (mediaData) {
                    videoDescription = mediaData.caption?.text || videoDescription;
                    const igComments = mediaData.comments?.items || [];
                    if (igComments.length > 0) commentsText = igComments.slice(0, 20).map((c: any) => c.text).join(" | ");
                }
            } catch (e) { console.warn("IG Info extraction failed"); }
        } else {
            const tikRes = await axios.get('https://www.tikwm.com/api/', { params: { url: rawUrl } });
            directVideoUrl = tikRes.data.data.play;
            videoDescription = tikRes.data.data.title || "No caption found";
            authorName = tikRes.data.data?.author?.nickname || "TikTok Creator";
            try {
                const cRes = await axios.get(`https://www.tikwm.com/api/comment/list?id=${tikRes.data.data.id}&url=${encodeURIComponent(rawUrl)}`);
                const list = cRes.data.data?.comments || [];
                if (list.length > 0) commentsText = list.slice(0, 20).map((c: any) => c.text).join(" | ");
            } catch (e) { console.warn("TT comments failed"); }
        }

        // --- שלב 2: הורדה ---
        const videoResponse = await axios({ url: directVideoUrl, method: 'get', responseType: 'stream' });
        const writer = fs.createWriteStream(tempFilePath);
        videoResponse.data.pipe(writer);
        await new Promise<void>((resolve, reject) => {
            writer.on('finish', () => resolve());
            writer.on('error', (err) => reject(err));
        });

        // --- שלב 3: Gemini (הפרומפט המקורי) ---
        const videoBase64 = fs.readFileSync(tempFilePath).toString("base64");
        const payload = {
            contents: [{
                parts: [
                    { text: `Analyze this restaurant review video.
         --- INPUT SOURCES ---
         1. CREATOR_CAPTION: "${videoDescription}"
         2. USER_COMMENTS: "${commentsText}"
         3. VIDEO_CONTENT: Visuals and Audio

         --- MISSION & RULES ---
         - NAME & ADDRESS: Search the CREATOR_CAPTION first. If the caption is "No caption found" or lacks info, use your visual intelligence to identify signs, menus, or landmarks in the video.
         - PRICE ANALYSIS (CRITICAL): Determine "price_level" as a NUMBER: 1 (Cheap), 2 (Normal), 3 (Expensive).
           * CROSS-REFERENCE: Look at the menu in the video AND scan USER_COMMENTS.
           * If users in comments mention "it's overpriced" or "too expensive", lean towards 3.
           * If NO mention of price exists in video OR comments, return 0.
         - COMMUNITY VOICE: Use USER_COMMENTS to summarize sentiment. If missing, describe the vibe from the video.
         - HIGHLIGHTS: Extract EXACTLY 5 short, punchy points (e.g., "Cheap lunch", "Amazing pasta").
         - DESCRIPTION: Write a detailed, coherent paragraph about the experience.

         STRICT JSON STRUCTURE:
         {
           "name": "Restaurant Name",
           "address": "Street, City, Israel",
           "cuisine": "Food type",
           "top_highlights": ["Point 1", "Point 2", "Point 3", "Point 4", "Point 5"],
           "full_description": "A detailed summary of the food, service and atmosphere.",
           "community_sentiment": "Summary of user comments.",
           "sentiment_score": "positive/neutral/negative",
           "must_order_dishes": ["Dish1", "Dish2"],
           "price_level": number,
           "recommendation_tags": ["Tag1", "Tag2"],
           "website": ""
         }
         Return ONLY valid JSON.` },
                    { inline_data: { mime_type: "video/mp4", data: videoBase64 } }
                ]
            }]
        };

        const gRes = await axios.post(`https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=${GEMINI_KEY}`, payload);
        const aiData = JSON.parse(gRes.data.candidates[0].content.parts[0].text.match(/\{[\s\S]*\}/)[0]);

        // --- שלב 4: Geocoding ---
        const rName = aiData.name || "Unknown";
        const geo = await axios.get(`https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(rName + " " + aiData.address)}&key=${MAPS_KEY}`);
        const finalAddr = geo.data.results[0]?.formatted_address || aiData.address;
        const loc = geo.data.results[0]?.geometry.location || { lat: 32.0853, lng: 34.7818 };

        // --- שלב 5: הכנת אובייקט וה-Thumbnail ---
        const realThumbnail = await fetchThumbnailUrl(rawUrl);
        const newRec = {
            videoUrl: rawUrl,
            source: source,
            reviewerName: authorName,
            thumbnailUrl: realThumbnail,
            top_highlights: aiData.top_highlights || [],
            full_description: aiData.full_description || "",
            community_sentiment: aiData.community_sentiment || "",
            price_level: aiData.price_level || 0,
            addedAt: Date.now()
        };

        // --- חיפוש חכם למניעת כפילויות ---
        let nameQuery = await restaurantsRef.where('userId', '==', userId).where('name', '==', rName).get();
        let docToUpdate = !nameQuery.empty ? nameQuery.docs[0] : null;

        if (!docToUpdate) {
            const addressQuery = await restaurantsRef.where('userId', '==', userId).where('address', '==', finalAddr).get();
            if (!addressQuery.empty) docToUpdate = addressQuery.docs[0];
        }

        if (docToUpdate) {
            // --- שלב 6: איחוד (הפרומפט המקורי) ---
            const targetDoc = docToUpdate;
            const existingData = targetDoc.data();

            const allRecs = [...(existingData.recommendations || []), newRec];

            const summaryPayload = {
                contents: [{
                    parts: [{ text: `Summarize these ${allRecs.length} reviews for "${rName}".
                       DATA: ${JSON.stringify(allRecs)}

                       STRICT RULES:
                       1. FINAL PRICE: Determine a unified "price_level" (1=Cheap, 2=Normal, 3=Expensive).
                          * Weigh the "price_level" from all reviews.
                          * If multiple USER_COMMENTS across different videos mention high costs, prioritize a higher score.
                          * If all reviews have 0 (no info), the final "price_level" MUST be 0.
                       2. Generate 4-5 very short "decision_chips" (max 3 words each) in English.
                       3. These must be punchy facts like "Handmade Pasta", "Authentic Vibes", "Expensive but worth it".
                       4. "unified_description": A single, very short sentence (max 15 words) in English summarizing the place.

                       Return ONLY JSON:
                       {
                         "price_level": number,
                         "unified_description": "...",
                         "decision_chips": ["chip1", "chip2", "chip3", "chip4"]
                       }` }]
                }]
            };

            const sRes = await axios.post(`https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=${GEMINI_KEY}`, summaryPayload);
            const summaryJson = JSON.parse(sRes.data.candidates[0].content.parts[0].text.match(/\{[\s\S]*\}/)[0]);

            await targetDoc.ref.update({
                recommendations: admin.firestore.FieldValue.arrayUnion(newRec),
                videoUrls: admin.firestore.FieldValue.arrayUnion(rawUrl),
                global_summary: summaryJson,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
        } else {
            // יצירת מסעדה חדשה
            await restaurantsRef.add({
                ...aiData,
                name: rName,
                thumbnailUrl: realThumbnail,
                address: finalAddr,
                location: loc,
                userId: userId,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                videoUrls: [rawUrl],
                recommendations: [newRec],
                global_summary: {
                    price_level: aiData.price_level,
                    unified_description: aiData.full_description.substring(0, 50) + "...",
                    decision_chips: aiData.top_highlights.slice(0, 3)
                },
                user_rating: 0,
                user_notes: ""
            });
        }

        if (fs.existsSync(tempFilePath)) fs.unlinkSync(tempFilePath);
        return snapshot.ref.update({ status: "completed" });

    } catch (error: any) {
        if (fs.existsSync(tempFilePath)) fs.unlinkSync(tempFilePath);
        console.error("ERROR:", error.message);
        return snapshot.ref.update({ status: "error", message: error.message });
    }
});