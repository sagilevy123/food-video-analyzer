from google.genai import types # תוודא שהוספת את ה-import הזה למעלה
from google import genai
import requests
from supabase import create_client, Client
import json
import time



# 1. הגדרת מפתחות (API Keys)
GEMINI_API_KEY = "AIzaSyDOjNi3Q3db1ZZ3l6q5lBtEXrR-pD9yRFU"
GOOGLE_MAPS_KEY = "AIzaSyCFB4c4uaUDrNqtJzE2QpdR_2kxPraquVo"

# פרטי החיבור (תמצא אותם ב-Settings -> API ב-Supabase)
SUPABASE_URL = "https://eerbtqfstshgndryykds.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVlcmJ0cWZzdHNoZ25kcnl5a2RzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY2OTY3ODUsImV4cCI6MjA4MjI3Mjc4NX0.QS4d5jRfrxPHFOroPBZ5J6dWZ9ZvYchgiuIKAkd3Rcg-ipLxf7thyle5B0rsLoEQ_B4PCixLO"

# 1. אתחול Gemini (משתמש ב-GEMINI_API_KEY)
# שים לב: ב-SDK החדש (google-genai) חייבים להגדיר api_key=...
client = genai.Client(api_key=GEMINI_API_KEY)

# 2. אתחול Supabase (משתמש ב-SUPABASE_URL ו-SUPABASE_KEY)
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


def save_to_db(name, address, lat, lng, dishes):
    data = {
        "name": name,
        "address": address,
        "lat": lat,
        "lng": lng,
        "recommended_dishes": dishes
    }
    # שמירה לטבלה
    result = supabase.table("restaurants").insert(data).execute()
    print("--- המידע נשמר בהצלחה בבסיס הנתונים! ---")
    return result


def get_restaurant_info(video_path):
    # הכרחת שימוש בגרסה היציבה v1
    client = genai.Client(
        api_key=GEMINI_API_KEY,
        http_options={'api_version': 'v1'}
    )

    try:
        print(f"--- מעלה וידאו: {video_path} ---")
        video_file = client.files.upload(file=video_path)

        while video_file.state.name != "ACTIVE":
            print(".", end="", flush=True)
            time.sleep(3)
            video_file = client.files.get(name=video_file.name)

        print("\n--- מנתח... ---")

        # שינוי שם המודל לפורמט המלא
        response = client.models.generate_content(
            model="gemini-1.5-flash",  # אם זה נכשל, נסה "models/gemini-1.5-flash"
            contents=[
                video_file,
                "Identify the restaurant and city. Return JSON: {\"search_query\": \"Name, City\", \"best_dish\": \"Dish\"}"
            ],
            config={'response_mime_type': 'application/json'}
        )

        ai_data = json.loads(response.text)
        print(f"✅ הצלחנו! המידע: {ai_data}")
        return ai_data

    except Exception as e:
        # כאן נדפיס את השגיאה המלאה כדי להבין מה קורה
        print(f"❌ שגיאה: {e}")
        return None


def get_maps_location(query):
    print(f"--- שלב 2: מחפש מיקום מדויק בגוגל מפות עבור: {query} ---")

    url = f"https://maps.googleapis.com/maps/api/place/textsearch/json?query={query}&key={GOOGLE_MAPS_KEY}"
    response = requests.get(url).json()

    if response.get('results'):
        place = response['results'][0]
        name = place['name']
        address = place['formatted_address']
        lat = place['geometry']['location']['lat']
        lng = place['geometry']['location']['lng']

        print(f"\n✅ נמצאה התאמה!")
        print(f"שם: {name}")
        print(f"כתובת: {address}")
        print(f"קואורדינטות: {lat}, {lng}")
        return lat, lng
    else:
        print("❌ לא נמצאה התאמה בגוגל מפות.")
        return None


def get_full_info_from_ai(video_path):
    client = genai.Client(api_key=GEMINI_API_KEY)

    with open(video_path, "rb") as f:
        # ביקשנו מה-AI להחזיר פורמט JSON בלבד
        prompt = """
        Analyze this video. Return ONLY a JSON object with:
        {
          "search_query": "Restaurant Name, City",
          "best_dish": "The main dish recommended"
        }
        """
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=[prompt, genai.types.Part.from_bytes(data=f.read(), mime_type="video/mp4")]
        )

    # פה הקסם קורה:
    # 1. לוקחים את הטקסט מה-AI (למשל '{"search_query": "Kiss...", "best_dish": "..."}')
    ai_text = response.text.strip()

    # 2. הופכים את הטקסט למשתנה מסוג JSON (מילון בפייתון)
    # אנחנו קוראים למשתנה הזה response_json
    response_json = json.loads(ai_text)

    return response_json


# --- הרצה סופית ---
# וודא שקובץ הסרטון נמצא באותה תיקייה ושינית את השם שלו כאן למטה
video_file = "v29044g50000d56mfffog65jqtcpu3lg.mov"

# שלב 1: הוצאת שם מהסרטון
search_term = get_restaurant_info(video_file)

# שלב 2: מציאת נקודה על המפה
# שלב ב': גוגל מפות מחזיר מילון (Dictionary) עם כל הפרטים
ai_data = get_full_info_from_ai("v29044g50000d56mfffog65jqtcpu3lg.mov")
location_data = get_maps_location(search_term)

# שלב ג': שליפת המשתנים מתוך התוצאה של גוגל
name = location_data['name']
addr = location_data['address']
lat = location_data['lat']
lng = location_data['lng']
dishes=ai_data['best_dish']

if location_data:
    print(f"\nבוצע! עכשיו אפשר לשמור את הנקודה {location_data} למפה של האפליקציה.")

# שלב ד': שמירה לבסיס הנתונים
save_to_db(name, addr, lat, lng, dishes)