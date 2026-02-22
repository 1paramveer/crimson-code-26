import cv2
import requests
import base64

API_KEY = "qkAZNqw1IfKmOzokdEqt"
URL = "https://serverless.roboflow.com/amans-workspace-gwpof/workflows/find-potholes"

cap = cv2.VideoCapture(0)

print("Camera started. Press Q to quit.")

while True:
    ret, frame = cap.read()

    if not ret:
        break

    _, buffer = cv2.imencode(".jpg", frame)
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

            print("POTHOLE DETECTED")

    cv2.imshow("RoadGuardian AI", frame)

    if cv2.waitKey(1) == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()
