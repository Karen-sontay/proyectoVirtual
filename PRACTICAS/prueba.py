from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

@app.route('/current_datetime', methods=['GET'])
def current_datetime():
    current_date_and_time = datetime.now()
    formatted_date_and_time = current_date_and_time.strftime('%Y-%m-%d %H:%M:%S')
    return jsonify({'current_datetime': formatted_date_and_time})

if __name__ == '__main__':
    app.run(debug=True)