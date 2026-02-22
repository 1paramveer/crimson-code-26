# 🛡 RoadGuardian AI

**AI-powered pothole detection & safer route planning** — built at Crimson Code 2026 hackathon.

RoadGuardian AI uses a YOLOv8 model (via Roboflow) to detect potholes from dashcam video in real-time, plots them on an interactive map, and routes drivers around dangerous road segments.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **AI Pothole Detection** | YOLOv8 model detects potholes from video/camera feed via Roboflow API |
| **Interactive Map Dashboard** | Leaflet.js map with clustered pothole markers, color-coded by severity |
| **Smart Routing** | OSRM-based route planning that counts potholes along the path |
| **Safer Alternatives** | Automatically suggests less risky routes using custom avoidance routing |
| **Address Search** | Nominatim autocomplete — type start/destination instead of clicking |
| **Heatmap Layer** | Toggle density heatmap overlay to visualize problem areas |
| **Manual Reporting** | Click-to-report mode — coordinates are snapped to nearest road |
| **Time Filters** | Filter pothole data by last 24h / 7 days / 30 days |
| **Dark Map Toggle** | Switch between standard and dark map tiles |
| **Analytics Dashboard** | Chart.js bar chart of daily detections + AI vs. manual breakdown |
| **Road Snapping** | All coordinates are snapped to nearest road via OSRM for accuracy |

---

## 🏗 Architecture

```
┌──────────────┐    Roboflow API     ┌──────────────────┐
│  Dashcam /   │ ──── YOLOv8 ──────► │  potholes.json   │
│  Webcam      │    Inference        │  (JSONL store)   │
└──────────────┘                     └────────┬─────────┘
                                              │
                                     ┌────────▼─────────┐
                                     │  Flask Backend    │
                                     │  (dashboard.py)   │
                                     │                   │
                                     │  /data  /route    │
                                     │  /report /analytics│
                                     └────────┬─────────┘
                                              │
                                     ┌────────▼─────────┐
                                     │  Leaflet.js Map   │
                                     │  + Chart.js       │
                                     │  (map.html)       │
                                     └──────────────────┘
```

**External APIs used:**
- [Roboflow](https://roboflow.com) — YOLOv8 pothole detection inference
- [OSRM](http://project-osrm.org) — routing, road snapping, alternative paths
- [Nominatim](https://nominatim.openstreetmap.org) — address geocoding/autocomplete

---

## 🚀 Quick Start

### Prerequisites
- Python 3.10+
- A [Roboflow](https://roboflow.com) API key (for video/camera detection)

### Setup

```bash
# Clone the repo
git clone https://github.com/1paramveer/crimson-code-26.git
cd crimson-code-26

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure API key (required for video/camera detection only)
cp .env.example .env
# Edit .env and add your Roboflow API key
```

### Run the Dashboard

```bash
python dashboard.py
# Opens at http://localhost:8000
```

### Run Pothole Detection (optional)

```bash
# From video file
python roboflow_video.py

# From live webcam
python roboflow_camera.py
```

---

## 📁 Project Structure

```
├── dashboard.py          # Flask backend — API endpoints & routing logic
├── templates/
│   └── map.html          # Frontend — Leaflet map, Chart.js, all UI
├── roboflow_video.py     # Detect potholes from video file
├── roboflow_camera.py    # Detect potholes from live webcam
├── potholes.json         # Pothole data store (JSONL format)
├── requirements.txt      # Python dependencies
├── .env.example          # Environment variable template
├── start_app.sh          # One-line startup script
└── README.md
```

---

## 🔌 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/` | Main map dashboard |
| `GET` | `/data` | Clustered pothole data (JSON) |
| `GET` | `/data?since=24h` | Time-filtered data (`24h`, `7d`, `30d`) |
| `POST` | `/route` | Calculate route with pothole count + safer alternative |
| `POST` | `/report` | Manually report a pothole (auto road-snapped) |
| `GET` | `/analytics` | Daily detection trend + source breakdown |

---

## 🛠 Tech Stack

- **Backend:** Python, Flask
- **Frontend:** Leaflet.js, Chart.js, vanilla JS
- **AI Model:** YOLOv8 (Roboflow hosted inference)
- **Routing:** OSRM (Open Source Routing Machine)
- **Geocoding:** Nominatim (OpenStreetMap)

---

## 👥 Team

Built at **Crimson Code 2026** — Washington State University

---

## 📄 License

MIT

