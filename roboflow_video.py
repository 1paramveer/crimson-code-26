import cv2
import requests
import base64
import geocoder
import datetime
import json
import os
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.environ.get("ROBOFLOW_API_KEY", "")
URL = os.environ.get("ROBOFLOW_WORKFLOW_URL", "https://serverless.roboflow.com/amans-workspace-gwpof/workflows/find-potholes")

if not API_KEY:
    print("⚠️  ROBOFLOW_API_KEY not set. Copy .env.example to .env and add your key.")
    exit(1)

VIDEO_PATH = "tested.mp4"

cap = cv2.VideoCapture(VIDEO_PATH)

frame_count = 0

print("Processing video...")

while cap.isOpened():

    ret, frame = cap.read()

    if not ret:
        break

    frame_count += 1

    # Process every 10th frame for speed
    if frame_count % 10 == 0:

        frame_small = cv2.resize(frame, (640, 480))

        _, buffer = cv2.imencode(".jpg", frame_small)
        img_base64 = base64.b64encode(buffer).decode("utf-8")

        payload = {
            "api_key": API_KEY,
            "inputs": {
                "image": {
                    "type": "base64",
                    "value": img_base64
                }
            }
        }

        response = requests.post(URL, json=payload)
        result = response.json()

        if "outputs" in result:

            predictions = result["outputs"][0]["predictions"]["predictions"]

            if len(predictions) > 0:

                # Get location
                g = geocoder.ip('me')
                lat, lng = g.latlng

                # Snap to nearest road so marker sits on road in Leaflet
                try:
                    snap_url = f"http://router.project-osrm.org/nearest/v1/driving/{lng},{lat}"
                    snap_resp = requests.get(snap_url, timeout=3)
                    snap_data = snap_resp.json()
                    if "waypoints" in snap_data and snap_data["waypoints"]:
                        wp = snap_data["waypoints"][0]
                        lat, lng = wp["location"][1], wp["location"][0]
                except Exception:
                    pass  # Use original coordinates if snapping fails

                timestamp = datetime.datetime.now().isoformat()

                pothole_data = {
                    "latitude": lat,
                    "longitude": lng,
                    "timestamp": timestamp,
                    "frame": frame_count
                }

                print("POTHOLE DETECTED:", pothole_data)

                with open("potholes.json", "a") as f:
                    f.write(json.dumps(pothole_data) + "\n")

                # Draw boxes
                for pred in predictions:

                    x = int(pred["x"])
                    y = int(pred["y"])
                    w = int(pred["width"])
                    h = int(pred["height"])

                    x1 = int(x - w/2)
                    y1 = int(y - h/2)
                    x2 = int(x + w/2)
                    y2 = int(y + h/2)

                    cv2.rectangle(frame, (x1,y1), (x2,y2), (0,255,0), 2)
                    cv2.putText(frame, "POTHOLE", (x1,y1-10),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0,255,0), 2)

    cv2.imshow("RoadGuardian AI - Video", frame)

    if cv2.waitKey(1) == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()

print("Video processing complete.")
