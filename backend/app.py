from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime
import json

# Initialize Flask app
app = Flask(__name__)

# Configure CORS
CORS(app, 
     origins=["*"],  # Configure this properly for production
     allow_headers=["*"],
     methods=["*"])

# Root endpoint
@app.route("/", methods=["GET"])
def root():
    """Root endpoint with basic API information"""
    return jsonify({
        "message": "Seismo Cardio API",
        "push_data": "/accelerometer-data",
        "version": "1.0.0",
        "health": "/health"
    })

# Health check endpoint
@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy", 
        "timestamp": datetime.now().isoformat()
    })

@app.route("/accelerometer-data", methods=["POST"])
def accelerometer_data():
    """Endpoint to receive and process accelerometer data"""
    try:
        # Get JSON data from request
        data = request.get_json()
        
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        return jsonify({
            "status": "success", 
            "message": "Data received successfully",
            "timestamp": datetime.now().isoformat(),
            "data_received": json.dumps(data, indent=4)
        }), 200
        
    except Exception as e:
        print(f"Error processing data: {str(e)}")
        return jsonify({
            "status": "error", 
            "message": str(e),
            "timestamp": datetime.now().isoformat()
        }), 500

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({
        "status": "error",
        "message": "Endpoint not found",
        "timestamp": datetime.now().isoformat()
    }), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({
        "status": "error",
        "message": "Internal server error",
        "timestamp": datetime.now().isoformat()
    }), 500

# Run the application
if __name__ == "__main__":
    app.run(host="0.0.0.0",port=8080,debug=True)