import os
import time
import json
import google.generativeai as genai
import googlemaps
import os
from dotenv import load_dotenv

# טעינת המשתנים מהקובץ הנסתר
load_dotenv()

# משיכת המפתחות
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GOOGLE_MAPS_KEY = os.getenv("GOOGLE_MAPS_KEY")

# בדיקה שהמפתחות נטענו
if not GEMINI_API_KEY or not GOOGLE_MAPS_KEY:
    print("❌ שגיאה: המפתחות לא נמצאו בקובץ .env")
    exit()
# --- אתחול השירותים ---
genai.configure(api_key=GEMINI_API_KEY)
model = genai.GenerativeModel('gemini-2.5-flash')
gmaps = googlemaps.Client(key=GOOGLE_MAPS_KEY)

def analyze_restaurant_locally(video_path):
    try:
        # 1. העלאת הווידאו
        print(f"--- מעלה וידאו: {video_path} ---")
        video_file = genai.upload_file(path=video_path)

        while video_file.state.name == "PROCESSING":
            print(".", end="", flush=True)
            time.sleep(3)
            video_file = genai.get_file(video_file.name)

        print("\n--- מנתח תוכן... ---")

        # 2. פרומפט מעודכן (ללא מנה מומלצת)
        # 2. פרומפט מדויק: סוג מסעדה + מה רואים בסרטון
        prompt = (
            "Identify the restaurant and city. "
            "For 'cuisine', use the specific description mentioned in the video (e.g., 'American Diner'). "
            "Also, look closely at the video and list 2-3 specific food items or dishes shown. "
            "Return ONLY JSON: {\"name\": \"Name\", \"city\": \"City\", \"cuisine\": \"Type\", \"dishes_shown\": [\"dish1\", \"dish2\"]}"
        )

        response = model.generate_content([video_file, prompt])

        # ניקוי ופירוק ה-JSON
        clean_json = response.text.replace('```json', '').replace('```', '').strip()
        data = json.loads(clean_json)

        # 3. קבלת קואורדינטות מגוגל מפות
        print(f"📍 מחפש מיקום במפות עבור: {data['name']}, {data['city']}...")
        geo_result = gmaps.geocode(f"{data['name']}, {data['city']}")

        # כאן אנחנו מגדירים אותם לראשונה
        if geo_result:
            lat = geo_result[0]['geometry']['location']['lat']  # שומר את קו הרוחב
            lng = geo_result[0]['geometry']['location']['lng']  # שומר את קו האורך
        else:
            # אם גוגל לא מצאה את המקום, ניתן להם ערך ברירת מחדל של 0
            lat, lng = 0, 0

        # 4. הדפסה מפורטת למסך
        print("\n" + "=" * 40)
        print(f"🍴 Restaurant: {data.get('name')}")
        print(f"🏙️ City: {data.get('city')}")
        print(f"🍕 Category: {data.get('cuisine')}")

        # הדפסת המנות שזוהו בסרטון
        dishes = data.get('dishes_shown', [])
        print(f"🍟 Spotted in video: {', '.join(dishes)}")

        print(f"🌐 Location: {lat}, {lng}")
        print("=" * 40)

    except Exception as e:
        print(f"\n❌ שגיאה: {e}")

if __name__ == "__main__":
    # וודא שהקובץ kiss_video.mov נמצא באותה תיקייה של הקוד
    path_to_video = "kiss_video.mov"
    analyze_restaurant_locally(path_to_video)