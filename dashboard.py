from flask import Flask, render_template, jsonify, request
import json
from collections import defaultdict
from datetime import datetime, timedelta
import math
import requests
import os

app = Flask(__name__)

# Get the project root directory
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
POTHOLES_FILE = os.path.join(PROJECT_ROOT, "potholes.json")

# ------------------------
# Load raw pothole reports
# ------------------------
def load_potholes():
    potholes = []
    try:
        if not os.path.exists(POTHOLES_FILE):
            print(f"⚠️ Potholes file not found: {POTHOLES_FILE}")
            return potholes
            
        with open(POTHOLES_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        potholes.append(json.loads(line))
                    except json.JSONDecodeError as e:
                        print(f"⚠️ Invalid JSON line: {line} - {e}")
    except Exception as e:
        print(f"❌ Error loading potholes: {type(e).__name__}: {e}")
    return potholes


# Snap coordinate to nearest road using OSRM (optional, for offline processing)
def snap_to_nearest_road(lat, lon):
    try:
        # OSRM nearest endpoint: /nearest/v1/driving/{lon},{lat}
        url = f"http://router.project-osrm.org/nearest/v1/driving/{lon},{lat}"
        response = requests.get(url, timeout=5)
        response.raise_for_status()
        data = response.json()
        
        if "waypoints" in data and len(data["waypoints"]) > 0:
            wp = data["waypoints"][0]
            # Return snapped coordinate as [lat, lon]
            return (wp["location"][1], wp["location"][0])
        return (lat, lon)
    except Exception as e:
        print(f"Warning: Could not snap coordinate ({lat}, {lon}): {e}")
        return (lat, lon)


# ------------------------
# Group nearby potholes
# ------------------------
def group_potholes(potholes):
    grouped = defaultdict(list)

    for p in potholes:
        key = (round(p["latitude"], 3), round(p["longitude"], 3))
        grouped[key].append(p)

    results = []

    for key, reports in grouped.items():
        try:
            avg_conf = sum(r.get("confidence", 0.8) for r in reports) / len(reports)
            latest = max(r.get("timestamp", "Unknown") for r in reports)

            # Use average of ORIGINAL coordinates for precise placement on road
            avg_lat = sum(r["latitude"] for r in reports) / len(reports)
            avg_lon = sum(r["longitude"] for r in reports) / len(reports)

            results.append({
                "latitude": round(avg_lat, 6),
                "longitude": round(avg_lon, 6),
                "count": len(reports),
                "avg_confidence": round(avg_conf, 2),
                "latest": latest
            })
        except Exception as e:
            print(f"Error processing pothole group {key}: {e}")
            continue

    return results


# ------------------------
# Distance helper
# ------------------------
def distance(lat1, lon1, lat2, lon2):
    return math.sqrt((lat1 - lat2)**2 + (lon1 - lon2)**2)


# ------------------------
# Count potholes near route
# ------------------------
def count_potholes_on_route(route_points, potholes):
    if not route_points or not potholes:
        return 0
    count = 0
    for p in potholes:
        for rp in route_points:
            if distance(p["latitude"], p["longitude"], rp[0], rp[1]) < 0.002:
                count += 1
                break
    return count




# Get OSRM route through optional waypoints
def get_osrm_route_via(start, destination, waypoints=None):
    try:
        # Build coordinate string: start;wp1;wp2;...;destination
        coords_parts = [f"{start[1]},{start[0]}"]
        if waypoints:
            for wp in waypoints:
                coords_parts.append(f"{wp[1]},{wp[0]}")
        coords_parts.append(f"{destination[1]},{destination[0]}")
        coords_str = ";".join(coords_parts)

        url = (f"http://router.project-osrm.org/route/v1/driving/"
               f"{coords_str}?overview=full&geometries=geojson")

        response = requests.get(url, timeout=5)
        response.raise_for_status()
        data = response.json()

        if "routes" not in data or len(data["routes"]) == 0:
            return None

        route_data = data["routes"][0]
        coords = route_data["geometry"]["coordinates"]
        route_points = [(coord[1], coord[0]) for coord in coords]
        distance_km = round(route_data["distance"] / 1000, 1)
        duration_min = round(route_data["duration"] / 60, 1)

        return {
            "points": route_points,
            "distance_km": distance_km,
            "duration_min": duration_min
        }
    except Exception:
        return None


# Generate alternative routes by offsetting waypoints perpendicular to the direct path
def generate_avoidance_routes(start, destination, potholes):
    mid_lat = (start[0] + destination[0]) / 2
    mid_lon = (start[1] + destination[1]) / 2

    # Direction vector from start to destination
    dx = destination[1] - start[1]
    dy = destination[0] - start[0]
    length = math.sqrt(dx * dx + dy * dy)

    if length < 0.001:
        return []

    # Perpendicular direction
    px = -dy / length
    py = dx / length

    # Try 4 offsets at midpoint: left/right, moderate/large
    offsets = [0.008, -0.008, 0.015, -0.015]
    candidates = []

    for offset in offsets:
        wp_lat = mid_lat + offset * px
        wp_lon = mid_lon + offset * py

        result = get_osrm_route_via(start, destination, [(wp_lat, wp_lon)])
        if result:
            count = count_potholes_on_route(result["points"], potholes)
            result["pothole_count"] = count
            candidates.append(result)
            if count == 0:
                return candidates  # Found perfect route, stop

    return candidates


# Get OSRM routes (with alternatives)
def get_osrm_routes(start, destination):
    try:
        url = (f"http://router.project-osrm.org/route/v1/driving/"
               f"{start[1]},{start[0]};{destination[1]},{destination[0]}"
               f"?overview=full&geometries=geojson&alternatives=true")

        response = requests.get(url, timeout=5)
        response.raise_for_status()
        data = response.json()

        if "routes" not in data or len(data["routes"]) == 0:
            print("No route found from OSRM")
            return []

        all_routes = []
        for route_data in data["routes"]:
            coords = route_data["geometry"]["coordinates"]
            # Convert [lon, lat] → [lat, lon]
            route = [(coord[1], coord[0]) for coord in coords]
            distance_km = round(route_data["distance"] / 1000, 1)
            duration_min = round(route_data["duration"] / 60, 1)
            all_routes.append({
                "points": route,
                "distance_km": distance_km,
                "duration_min": duration_min
            })
        return all_routes
    except Exception as e:
        print(f"Error fetching routes from OSRM: {e}")
        return []


# Legacy wrapper for index route
def get_osrm_route(start, destination):
    routes = get_osrm_routes(start, destination)
    if routes:
        return routes[0]["points"]
    return []


# Calculate center from pothole data
def calculate_center(potholes):
    if not potholes:
        return (46.7315, -117.1817)  # Default fallback
    
    avg_lat = sum(p["latitude"] for p in potholes) / len(potholes)
    avg_lon = sum(p["longitude"] for p in potholes) / len(potholes)
    return (avg_lat, avg_lon)


@app.route("/")
def index():
    try:
        potholes = load_potholes()
        grouped = group_potholes(potholes)

        # Calculate center from actual pothole data
        center = calculate_center(potholes)
        start = center
        destination = (center[0] + 0.015, center[1] + 0.015)

        route = get_osrm_route(start, destination)
        pothole_count = count_potholes_on_route(route, potholes)

        return render_template(
            "map.html",
            total_reports=len(potholes),
            pothole_count=pothole_count,
            route=route,
            center_lat=center[0],
            center_lon=center[1]
        )
    except Exception as e:
        print(f"Error rendering index: {e}")
        return f"<h1>Error loading dashboard</h1><p>{e}</p>", 500


# 🔥 Live data endpoint (NO page refresh)
@app.route("/data", methods=['GET'])
def data():
    try:
        potholes = load_potholes()

        # Optional time filter: ?since=24h | 7d | 30d
        since = request.args.get("since", "")
        if since:
            now = datetime.now()
            delta_map = {"24h": timedelta(hours=24), "7d": timedelta(days=7), "30d": timedelta(days=30)}
            delta = delta_map.get(since)
            if delta:
                cutoff = now - delta
                filtered = []
                for p in potholes:
                    try:
                        ts = datetime.strptime(p.get("timestamp", ""), "%Y-%m-%d %H:%M")
                        if ts >= cutoff:
                            filtered.append(p)
                    except (ValueError, TypeError):
                        filtered.append(p)  # keep entries with unparseable timestamps
                potholes = filtered

        grouped = group_potholes(potholes)
        return jsonify(grouped)
    except Exception as e:
        print(f"Error in /data endpoint: {e}")
        return jsonify({"error": str(e)}), 500


# 📍 Manual pothole report
@app.route("/report", methods=['POST'])
def report_pothole():
    try:
        data = request.get_json()
        if not data or "latitude" not in data or "longitude" not in data:
            return jsonify({"error": "Missing latitude or longitude"}), 400

        lat = float(data["latitude"])
        lon = float(data["longitude"])

        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            return jsonify({"error": "Coordinates out of range"}), 400

        # Snap to nearest road
        snapped_lat, snapped_lon = snap_to_nearest_road(lat, lon)

        entry = {
            "latitude": round(snapped_lat, 6),
            "longitude": round(snapped_lon, 6),
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M"),
            "confidence": 0.75,
            "source": "manual"
        }

        with open(POTHOLES_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")

        return jsonify({"status": "ok", "snapped": {"lat": entry["latitude"], "lon": entry["longitude"]}})
    except Exception as e:
        print(f"Error in /report endpoint: {e}")
        return jsonify({"error": str(e)}), 500


# 📊 Analytics data for charts
@app.route("/analytics", methods=['GET'])
def analytics():
    try:
        potholes = load_potholes()

        # Count potholes per day
        daily = defaultdict(int)
        for p in potholes:
            ts = p.get("timestamp", "")
            try:
                day = datetime.strptime(ts, "%Y-%m-%d %H:%M").strftime("%Y-%m-%d")
            except (ValueError, TypeError):
                day = "Unknown"
            daily[day] += 1

        # Sort by date
        sorted_days = sorted(daily.items(), key=lambda x: x[0])

        # Source breakdown
        sources = defaultdict(int)
        for p in potholes:
            sources[p.get("source", "ai")] += 1

        return jsonify({
            "daily": [{"date": d, "count": c} for d, c in sorted_days],
            "total": len(potholes),
            "sources": dict(sources)
        })
    except Exception as e:
        print(f"Error in /analytics endpoint: {e}")
        return jsonify({"error": str(e)}), 500


# 🗺️ Route calculation endpoint
@app.route("/route", methods=['POST'])
def calculate_route():
    try:
        request_data = request.get_json()
        
        if not request_data or "start" not in request_data or "destination" not in request_data:
            return jsonify({"error": "Missing start or destination"}), 400
        
        start = tuple(request_data["start"])
        destination = tuple(request_data["destination"])
        
        # Validate coordinates
        if not all(isinstance(x, (int, float)) for x in start + destination):
            return jsonify({"error": "Invalid coordinates"}), 400
        
        # Get all routes from OSRM (with alternatives)
        all_routes = get_osrm_routes(start, destination)
        
        if not all_routes:
            return jsonify({"error": "Could not calculate route"}), 400
        
        # Count potholes on each route
        potholes = load_potholes()
        
        primary = all_routes[0]
        primary_count = count_potholes_on_route(primary["points"], potholes)
        
        # Find the safest alternative (fewest potholes)
        safest_alt = None
        safest_alt_count = primary_count
        
        # 1) Check OSRM-provided alternatives first
        for alt in all_routes[1:]:
            alt_count = count_potholes_on_route(alt["points"], potholes)
            if alt_count < safest_alt_count:
                safest_alt = alt
                safest_alt_count = alt_count
        
        # 2) If primary is risky and no OSRM alt is better, generate our own
        if primary_count > 1 and (safest_alt is None or safest_alt_count >= primary_count):
            avoidance_routes = generate_avoidance_routes(start, destination, potholes)
            for candidate in avoidance_routes:
                if candidate["pothole_count"] < safest_alt_count:
                    safest_alt = candidate
                    safest_alt_count = candidate["pothole_count"]
        
        result = {
            "route": primary["points"],
            "pothole_count": primary_count,
            "distance_km": primary["distance_km"],
            "duration_min": primary["duration_min"],
            "start": start,
            "destination": destination
        }
        
        # Include safer alternative if it has fewer potholes
        if safest_alt and safest_alt_count < primary_count:
            result["alternative"] = {
                "route": safest_alt["points"],
                "pothole_count": safest_alt_count,
                "distance_km": safest_alt["distance_km"],
                "duration_min": safest_alt["duration_min"]
            }
        
        return jsonify(result)
    
    except Exception as e:
        print(f"Error in /route endpoint: {e}")
        return jsonify({"error": str(e)}), 500


@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404


@app.errorhandler(500)
def server_error(error):
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    print(f"Starting RoadGuardian AI Dashboard...")
    print(f"Potholes file: {POTHOLES_FILE}")
    print(f"File exists: {os.path.exists(POTHOLES_FILE)}")
    print(f"\n🚀 Opening http://localhost:8000 in your browser...")
    app.run(debug=True, host="0.0.0.0", port=8000)