import os
import json
import requests
import secrets
import time
import threading
from datetime import datetime, date
from flask import Flask, render_template_string, request, session, redirect, jsonify

# ==========================================
# ⚙️ CONFIGURATION
# ==========================================
SECRET_KEY = secrets.token_hex(32)
VERSION = "6.1 Classic Render"

ROOT_PASSWORD = "T8#yM4!qL9*vX2z"      
AUTH_TOKEN = "Xk#9mP!vL2$rT8#q"       

KEYS_FILE = "api_keys.json"
SETTINGS_FILE = "api_settings.json"
ANALYTICS_FILE = "analytics.json"
CUSTOM_APIS_FILE = "custom_apis.json"
RATE_LIMIT_FILE = "rate_limits.json"

# Yeh lock aapki files ko corrupt hone se bachayega
DATA_LOCK = threading.RLock()

API_LIST = [
    ("number", "📱 Number Info"), ("number_adv", "🔥 Number Info Advance"),
    ("aadhaar", "🪪 Aadhaar Info"), ("aadhaar_adv", "⚡ Aadhaar Info Advance"),
    ("email", "📧 Email Info"), ("vehicle", "🚗 Vehicle Info"),
    ("instagram", "📸 Instagram Info"), ("vehicle_owner", "🏍️ Vehicle to Owner"),
    ("truecaller", "📞 Truecaller"), ("telegram", "✈️ Telegram Info"),
    ("freefire", "🎮 Free Fire Info"), ("rc", "🚘 RC Number Info"),
    ("github", "💻 Github Info"), ("family", "👨‍👩‍👧 Family Info"),
    ("ip", "🌐 IP Info"), ("ifsc", "🏦 IFSC Info"),
    ("pakistan", "🇵🇰 Pakistan Number Info"), ("pincode", "📮 Pincode Info"),
    ("gst", "🏢 GST Info"), ("imei", "📱 IMEI Info"),
    ("pan", "🪪 PAN Info"), ("snapchat", "👻 Snapchat Info"),
    ("weather", "🌤️ Weather Info"), ("bgmi", "🎮 BGMI Info"),
    ("upi", "💳 UPI Info"), ("challan", "🚦 Challan Info"),
    ("ration", "🪪 Ration Info")
]

DEFAULT_QUERIES = {
    "number": "9876543210", "number_adv": "9876543210",
    "aadhaar": "123456789012", "aadhaar_adv": "123456789012",
    "email": "rohit5@gmail.com", "vehicle": "BR06PE8167",
    "instagram": "therock", "vehicle_owner": "BR06PE8167",
    "truecaller": "9876543210", "telegram": "@monk",
    "freefire": "12345678", "rc": "BR06PE8167",
    "github": "aditya", "family": "query_here",
    "ip": "8.8.8.8", "ifsc": "SBIN0001234",
    "pakistan": "03001234567", "pincode": "400001",
    "gst": "22AAAAA0000A1Z5", "imei": "353010111111110",
    "pan": "ABCDE1234F", "snapchat": "user123",
    "weather": "Indore", "bgmi": "1234567890",
    "upi": "example@upi", "challan": "BR06PE8167",
    "ration": "query_here"
}

DEFAULT_SETTINGS = {"root_password": ROOT_PASSWORD, "auth_token": AUTH_TOKEN, "rate_limit_per_minute": 60}
for api_id, _ in API_LIST:
    DEFAULT_SETTINGS[f"{api_id}_api"] = ""
    DEFAULT_SETTINGS[f"{api_id}_maintenance"] = False

# ==========================================
# 📁 SECURE FILE HELPERS
# ==========================================
def load_data(filepath, default_data):
    with DATA_LOCK:
        if os.path.exists(filepath):
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except (json.JSONDecodeError, ValueError):
                return default_data
        return default_data

def save_data(filepath, data):
    with DATA_LOCK:
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=4, ensure_ascii=False)

def get_keys():
    data = load_data(KEYS_FILE, {})
    today_str = str(date.today())
    updated = False
    for k, v in data.items():
        if v.get('last_used_date') != today_str:
            v['used'] = 0
            v['last_used_date'] = today_str
            updated = True
    if updated: save_data(KEYS_FILE, data)
    return data

def get_settings():
    settings = load_data(SETTINGS_FILE, DEFAULT_SETTINGS)
    for k, v in DEFAULT_SETTINGS.items():
        if k not in settings: settings[k] = v
    return settings

def get_custom_apis():
    return load_data(CUSTOM_APIS_FILE, {})

def save_custom_api(name, url):
    custom = get_custom_apis()
    custom[name] = {"url": url, "maintenance": False}
    save_data(CUSTOM_APIS_FILE, custom)

def delete_custom_api(name):
    custom = get_custom_apis()
    if name in custom:
        del custom[name]
        save_data(CUSTOM_APIS_FILE, custom)

def update_analytics(api_type, ip, api_key, status, query):
    analytics = load_data(ANALYTICS_FILE, {"total_requests": 0, "daily_requests": {}, "api_usage": {}})
    analytics["total_requests"] += 1
    today = str(date.today())
    analytics.setdefault("daily_requests", {})[today] = analytics["daily_requests"].get(today, 0) + 1
    display_name = api_type.upper()
    analytics.setdefault("api_usage", {})[display_name] = analytics["api_usage"].get(display_name, 0) + 1
    save_data(ANALYTICS_FILE, analytics)

def rate_limit_check(ip):
    rate_limits = load_data(RATE_LIMIT_FILE, {})
    current_minute = int(time.time() / 60)
    if ip not in rate_limits or rate_limits[ip].get("minute") != current_minute:
        rate_limits[ip] = {"minute": current_minute, "count": 0}
    rate_limits[ip]["count"] += 1
    save_data(RATE_LIMIT_FILE, rate_limits)
    return rate_limits[ip]["count"] <= get_settings().get("rate_limit_per_minute", 60)

# ==========================================
# 🌐 FLASK APP
# ==========================================
app = Flask(__name__)
app.secret_key = SECRET_KEY

def root_required(f):
    def decorated_function(*args, **kwargs):
        if not session.get('root_logged_in'): return redirect('/dashboard')
        return f(*args, **kwargs)
    decorated_function.__name__ = f.__name__
    return decorated_function

def admin_required(f):
    def decorated_function(*args, **kwargs):
        if not session.get('admin_logged_in'): return redirect('/admin')
        return f(*args, **kwargs)
    decorated_function.__name__ = f.__name__
    return decorated_function

# ==========================================
# 🎨 BRIGHT WHITE PREMIUM UI TEMPLATE
# ==========================================
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>API Hub v{{ version }}</title>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Plus Jakarta Sans', sans-serif; }
        body { background-color: #f3f4f6; color: #1f2937; min-height: 100vh; display: flex; flex-direction: column; align-items: center; }
        .main-container { width: 100%; max-width: 900px; padding: 20px; }
        .card { background: #ffffff; border-radius: 16px; padding: 24px; margin-bottom: 20px; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.03); border: 1px solid #e5e7eb; transition: all 0.3s ease; }
        .hub-header { display: flex; flex-direction: column; align-items: center; text-align: center; padding: 30px 20px; }
        .logo-section { display: flex; align-items: center; justify-content: center; gap: 12px; margin-bottom: 8px; }
        .logo-section i { font-size: 40px; color: #ff5722; }
        .logo-section h1 { font-size: 28px; font-weight: 800; color: #f97316; letter-spacing: -0.5px; }
        .version-text { font-size: 13px; color: #6b7280; font-weight: 600; margin-bottom: 20px; }
        .action-buttons { display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; }
        .pill-btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 16px; border-radius: 30px; font-size: 13px; font-weight: 700; cursor: pointer; text-decoration: none; border: none; transition: 0.2s; }
        .btn-online { background: #ecfdf5; color: #059669; border: 1px solid #10b981; }
        .btn-refresh { background: #eff6ff; color: #2563eb; border: 1px solid #3b82f6; }
        .btn-refresh:hover { background: #3b82f6; color: white; }
        .btn-logout { background: #fef2f2; color: #dc2626; border: 1px solid #ef4444; }
        .btn-logout:hover { background: #ef4444; color: white; }
        .btn-support { background: #fdf4ff; color: #9333ea; border: 1px solid #a855f7; }
        .btn-support:hover { background: #a855f7; color: white; }
        .stats-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; margin-bottom: 20px; }
        .stat-box { background: #ffffff; border-radius: 16px; padding: 24px; text-align: center; box-shadow: 0 4px 15px rgba(0, 0, 0, 0.02); border: 1px solid #e5e7eb; display: flex; flex-direction: column; align-items: center; justify-content: center; }
        .stat-icon { font-size: 24px; margin-bottom: 12px; }
        .stat-value { font-size: 26px; font-weight: 800; color: #f97316; margin-bottom: 4px; }
        .stat-label { font-size: 12px; color: #6b7280; font-weight: 600; }
        .section-title { display: flex; align-items: center; gap: 8px; font-size: 18px; font-weight: 800; color: #3b82f6; margin-bottom: 20px; }
        .form-group { margin-bottom: 16px; }
        .form-group label { display: block; font-size: 11px; font-weight: 800; color: #374151; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px; }
        .form-control { width: 100%; padding: 12px 16px; border: 2px solid #e5e7eb; border-radius: 10px; font-size: 14px; color: #1f2937; background: #f9fafb; transition: 0.3s; outline: none; font-weight: 600; }
        .form-control:focus { border-color: #f97316; background: #ffffff; box-shadow: 0 0 0 3px rgba(249, 115, 22, 0.1); }
        .submit-btn { width: 100%; padding: 14px; border-radius: 10px; border: none; background: #10b981; color: white; font-weight: 800; font-size: 15px; cursor: pointer; transition: 0.3s; display: flex; align-items: center; justify-content: center; gap: 8px; }
        .submit-btn:hover { background: #059669; box-shadow: 0 4px 15px rgba(16, 185, 129, 0.3); }
        .btn-warning { background: #f59e0b; color: white; }
        .btn-warning:hover { background: #d97706; box-shadow: 0 4px 15px rgba(245, 158, 11, 0.3); }
        .table-responsive { overflow-x: auto; border-radius: 10px; border: 1px solid #e5e7eb; }
        table { width: 100%; border-collapse: collapse; background: #fff; min-width: 600px; }
        th { background: #f9fafb; padding: 12px; text-align: left; font-size: 11px; color: #6b7280; font-weight: 800; text-transform: uppercase; }
        td { padding: 12px; border-top: 1px solid #e5e7eb; font-size: 13px; font-weight: 600; color: #374151; }
        .badge { padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: 800; }
        .badge-active { background: #dcfce7; color: #059669; }
        .badge-expired { background: #fee2e2; color: #dc2626; }
        .url-box { background: #f3f4f6; padding: 6px 10px; border-radius: 6px; font-family: monospace; font-size: 11px; color: #4b5563; word-break: break-all; }
        .footer { text-align: center; padding: 20px; color: #6b7280; font-size: 13px; font-weight: 600; }
    </style>
</head>
<body>

<div class="main-container">
    {% if not session.root_logged_in and request.path == '/dashboard' %}
        <div class="card" style="max-width: 400px; margin: 80px auto; text-align: center; padding: 40px 24px;">
            <i class="fas fa-fingerprint" style="font-size: 50px; color: #f97316; margin-bottom: 15px;"></i>
            <h2 style="font-weight: 800; color: #1f2937; margin-bottom: 20px;">API Login</h2>
            <form method="POST" action="/login">
                <input type="password" name="password" class="form-control" placeholder="Dashboard Password" required style="margin-bottom: 15px;">
                <button type="submit" class="submit-btn" style="background: #f97316;">Access System</button>
            </form>
        </div>
    {% elif not session.admin_logged_in and request.path == '/admin' %}
        <div class="card" style="max-width: 400px; margin: 80px auto; text-align: center; padding: 40px 24px; border-top: 4px solid #ef4444;">
            <i class="fas fa-shield-halved" style="font-size: 50px; color: #ef4444; margin-bottom: 15px;"></i>
            <h2 style="font-weight: 800; color: #ef4444; margin-bottom: 20px;">Admin Override</h2>
            <form method="POST" action="/admin_login">
                <input type="password" name="auth_token" class="form-control" placeholder="Auth Token Required" required style="margin-bottom: 15px;">
                <button type="submit" class="submit-btn" style="background: #ef4444;">Authenticate</button>
            </form>
        </div>
    {% else %}
        
        <div class="card hub-header">
            <div class="logo-section">
                <i class="fas fa-robot"></i>
                <h1>Aditya API Hub</h1>
            </div>
            <div class="version-text">v{{ version }} • Premium API Management</div>
            <div class="action-buttons">
                <span class="pill-btn btn-online"><i class="fas fa-circle" style="font-size: 8px;"></i> ONLINE</span>
                <button onclick="location.reload()" class="pill-btn btn-refresh"><i class="fas fa-sync-alt"></i> Refresh</button>
                {% if request.path == '/dashboard' %}
                    <a href="https://t.me/AdityaXcyber" target="_blank" class="pill-btn btn-support"><i class="fab fa-telegram-plane"></i> Support</a>
                    <a href="/logout" class="pill-btn btn-logout"><i class="fas fa-sign-out-alt"></i> Logout</a>
                {% else %}
                    <a href="/dashboard" class="pill-btn btn-refresh"><i class="fas fa-home"></i> Dashboard</a>
                    <a href="/admin_logout" class="pill-btn btn-logout"><i class="fas fa-sign-out-alt"></i> Logout</a>
                {% endif %}
            </div>
        </div>

        {% if request.path == '/dashboard' %}
            <div class="stats-grid">
                <div class="stat-box">
                    <div class="stat-icon" style="color: #6b7280;"><i class="fas fa-key"></i></div>
                    <div class="stat-value">{{ keys|length }}</div>
                    <div class="stat-label">Total API Keys</div>
                </div>
                <div class="stat-box">
                    <div class="stat-icon" style="color: #10b981;"><i class="fas fa-chart-line"></i></div>
                    <div class="stat-value">{{ analytics.total_requests|default(0) }}</div>
                    <div class="stat-label">Total Requests</div>
                </div>
                <div class="stat-box">
                    <div class="stat-icon" style="color: #f59e0b;"><i class="far fa-calendar-check"></i></div>
                    <div class="stat-value">{{ analytics.daily_requests.get(today, 0)|default(0) }}</div>
                    <div class="stat-label">Today's Requests</div>
                </div>
                <div class="stat-box">
                    <div class="stat-icon" style="color: #8b5cf6;"><i class="fas fa-server"></i></div>
                    <div class="stat-value">{{ active_apis_count }}</div>
                    <div class="stat-label">Active APIs</div>
                </div>
            </div>

            <div class="card">
                <div class="section-title" style="color: #10b981;">
                    <i class="fas fa-plus-circle"></i> Generate New API Key
                </div>
                <form method="POST" action="/generate">
                    <div class="form-group">
                        <label>Key Name</label>
                        <input type="text" name="key_name" class="form-control" placeholder="e.g., premium_user" required>
                    </div>
                    <div class="form-group">
                        <label>Daily Limit</label>
                        <input type="number" name="limit" class="form-control" placeholder="0 = Unlimited" required>
                    </div>
                    <div class="form-group">
                        <label>Expiry Date</label>
                        <input type="date" name="expiry" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label>API Type</label>
                        <select name="type" class="form-control" style="cursor: pointer;">
                            {% for api_id, api_name in api_list %}
                                {% if settings[api_id + '_maintenance'] %}
                                    <option value="{{ api_id }}" disabled>{{ api_name }} (Maintenance)</option>
                                {% else %}
                                    <option value="{{ api_id }}">🟢 {{ api_name }}</option>
                                {% endif %}
                            {% endfor %}
                            {% for api_name, info in custom_apis.items() %}
                                {% if not info.maintenance %}
                                    <option value="{{ api_name }}">🔵 {{ api_name|upper }} (Custom)</option>
                                {% endif %}
                            {% endfor %}
                        </select>
                    </div>
                    <button type="submit" class="submit-btn"><i class="fas fa-key"></i> Create API Key</button>
                </form>
            </div>

            <div class="card">
                <div class="section-title">
                    <i class="fas fa-database"></i> API Key Database
                </div>
                <div class="table-responsive">
                    <table>
                        <thead><tr><th>Name</th><th>API Key</th><th>Type</th><th>Usage</th><th>Expiry</th><th>Status</th><th>Endpoint URL</th><th>Action</th></tr></thead>
                        <tbody>
                            {% for k, v in keys %}
                            <tr>
                                <td style="color: #3b82f6;">{{ v.username|default(k) }}</td>
                                <td style="color: #3b82f6; font-family: monospace;">{{ k }}</td>
                                <td>{{ v.api_type|upper }}</td>
                                <td>{{ v.used }} / {% if v.limit == 0 %}∞{% else %}{{ v.limit }}{% endif %}</td>
                                <td>{{ v.expiry_date }}</td>
                                <td>{% if v.expiry_date < today %}<span class="badge badge-expired">Expired</span>{% else %}<span class="badge badge-active">Active</span>{% endif %}</td>
                                <td>
                                    <div class="url-box" id="url_{{ loop.index }}">{{ host_url }}api/info?key={{ v.public_key|default(v.username|default(k)) }}&service={{ v.api_type }}&query={{ default_queries.get(v.api_type, 'TARGET_DATA') }}</div>
                                </td>
                                <td>
                                    <form method="POST" action="/delete_key" style="margin:0;">
                                        <input type="hidden" name="key_name" value="{{ k }}">
                                        <button type="submit" style="background:#fee2e2; border:none; color:#dc2626; padding:6px 12px; border-radius:6px; cursor:pointer; font-weight:700;"><i class="fas fa-trash"></i></button>
                                    </form>
                                </td>
                            </tr>
                            {% endfor %}
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="card" style="border: 1px solid #fcd34d;">
                <div class="section-title" style="color: #f59e0b;">
                    <i class="fas fa-tachometer-alt"></i> Rate Limit Configuration
                </div>
                <form method="POST" action="/update_rate_limit">
                    <div class="form-group">
                        <label>RATE LIMIT (REQUESTS/MINUTE)</label>
                        <input type="number" name="rate_limit_per_minute" class="form-control" value="{{ settings.rate_limit_per_minute }}" required>
                    </div>
                    <button type="submit" class="submit-btn btn-warning"><i class="fas fa-save"></i> Update Configuration</button>
                </form>
            </div>

            <div class="card" style="border: 1px solid #bfdbfe;">
                <div class="section-title" style="color: #3b82f6;">
                    <i class="fas fa-chart-bar"></i> Analytics
                </div>
                <div style="background: #f9fafb; border-radius: 12px; padding: 20px; border: 1px solid #e5e7eb;">
                    <div style="display: flex; justify-content: space-between; padding-bottom: 12px; border-bottom: 2px solid #e5e7eb; margin-bottom: 12px; font-weight: 800; color: #3b82f6; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px;">
                        <span>API Usage:</span>
                        <span>Hits</span>
                    </div>
                    {% for api, count in analytics.api_usage.items() %}
                    <div style="display: flex; justify-content: space-between; align-items: center; padding: 12px 0; border-bottom: 1px solid #e5e7eb; font-size: 14px; font-weight: 700; color: #4b5563;">
                        <span style="letter-spacing: 0.5px;">{{ api }}</span>
                        <span style="color: #3b82f6; background: #eff6ff; padding: 4px 12px; border-radius: 20px; font-size: 13px;">{{ count }}</span>
                    </div>
                    {% else %}
                    <div style="text-align: center; padding: 20px; color: #9ca3af; font-size: 13px; font-weight: 600;">No API usage data yet.</div>
                    {% endfor %}
                    <div style="text-align: center; margin-top: 20px; font-size: 12px; color: #9ca3af; font-weight: 700;">
                        &lt;/&gt; Aditya API Hub
                    </div>
                </div>
            </div>

        {% elif request.path == '/admin' %}
            <div class="stats-grid">
                <div class="stat-box" style="border-left: 4px solid #ef4444; padding: 20px;">
                    <h3 style="color:#ef4444; font-size:16px; margin-bottom:10px; font-weight: 800;">Security Core</h3>
                    <form method="POST" action="/change_pwd" style="width:100%;">
                        <input type="password" name="old_pwd" class="form-control" placeholder="Old Password" required style="margin-bottom:8px;">
                        <input type="password" name="auth_token" class="form-control" placeholder="Auth Token" required style="margin-bottom:8px;">
                        <input type="password" name="new_pwd" class="form-control" placeholder="New Password" required style="margin-bottom:10px;">
                        <button type="submit" class="submit-btn" style="background:#ef4444; padding: 10px;">Update</button>
                    </form>
                </div>
                
                <div class="stat-box" style="border-left: 4px solid #8b5cf6; padding: 20px;">
                    <h3 style="color:#8b5cf6; font-size:16px; margin-bottom:10px; font-weight: 800;">Custom APIs</h3>
                    <form method="POST" action="/add_custom_api" style="width:100%;">
                        <input type="text" name="api_name" class="form-control" placeholder="API Name" required style="margin-bottom:8px;">
                        <input type="url" name="api_url" class="form-control" placeholder="Target URL" required style="margin-bottom:10px;">
                        <button type="submit" class="submit-btn" style="background:#8b5cf6; padding: 10px;">Add Custom API</button>
                    </form>
                </div>
            </div>

            {% if custom_apis %}
            <div class="card" style="border-left: 4px solid #8b5cf6;">
                <div class="section-title" style="color: #8b5cf6;"><i class="fas fa-list"></i> Existing Custom APIs</div>
                {% for name, info in custom_apis.items() %}
                <div style="display:flex;justify-content:space-between;align-items:center;background:#f9fafb;padding:12px 16px;border-radius:10px;margin-bottom:8px;border: 1px solid #e5e7eb;">
                    <span style="font-weight:700; color: #1f2937;">{{ name|upper }}</span>
                    <span style="font-size:12px;color:#6b7280; font-family: monospace;">{{ info.url }}</span>
                    <form method="POST" action="/delete_custom_api" style="display:inline; margin:0;">
                        <input type="hidden" name="api_name" value="{{ name }}">
                        <button type="submit" style="background:transparent;border:none;color:#ef4444;cursor:pointer; font-size: 16px;"><i class="fas fa-trash"></i></button>
                    </form>
                </div>
                {% endfor %}
            </div>
            {% endif %}

            <div class="card">
                <div class="section-title" style="color: #3b82f6;"><i class="fas fa-sliders-h"></i> Endpoint Management</div>
                <form method="POST" action="/update_endpoints">
                    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px;">
                    {% for api_id, api_name in api_list %}
                        <div style="background:#f9fafb; padding:15px; border-radius:10px; border:1px solid #e5e7eb;">
                            <label style="display:block; font-weight:800; font-size:13px; margin-bottom:8px; color:#1f2937;">{{ api_name }}</label>
                            <input type="text" name="{{ api_id }}_api" class="form-control" placeholder="Backend URL" value="{{ settings.get(api_id + '_api', '') }}" style="margin-bottom:10px;">
                            <label style="font-size:12px; font-weight:700; color:#dc2626; cursor:pointer;">
                                <input type="checkbox" name="{{ api_id }}_maintenance" {% if settings.get(api_id + '_maintenance') %}checked{% endif %}> Under Maintenance
                            </label>
                        </div>
                    {% endfor %}
                    </div>
                    <button type="submit" class="submit-btn" style="margin-top: 20px; background:#3b82f6;"><i class="fas fa-save"></i> Save All Endpoints</button>
                </form>
            </div>
        {% endif %}
        
        <div class="footer">
            Credit: <span style="color: #f97316;">@Aditya_dark0</span> • <a href="https://t.me/AdityaXcyber" target="_blank" style="color:#3b82f6;text-decoration:none;">Channel</a>
        </div>
    {% endif %}
</div>

</body>
</html>
"""

# ==========================================
# 🌐 ROUTES
# ==========================================

@app.route('/', strict_slashes=False)
def index():
    if not session.get('root_logged_in'):
        return app.response_class(
            response=json.dumps({"status": "API is Active", "Credit": {"Username": "@Aditya_dark0", "Channel": "https://t.me/AdityaXcyber"}}, ensure_ascii=False),
            status=200,
            mimetype='application/json; charset=utf-8'
        )
    return redirect('/dashboard')

@app.route('/dashboard', strict_slashes=False)
def dashboard():
    if not session.get('root_logged_in'):
        return render_template_string(HTML_TEMPLATE, version=VERSION)
    
    settings = get_settings()
    custom_apis = get_custom_apis()
    keys_dict = get_keys()
    sorted_keys = sorted(keys_dict.items(), key=lambda x: x[1].get('created_at', ''), reverse=True)
    
    active_count = 0
    for api_id, _ in API_LIST:
        if not settings.get(f"{api_id}_maintenance"):
            active_count += 1
    for c_api in custom_apis.values():
        if not c_api.get('maintenance', False):
            active_count += 1

    analytics_data = load_data(ANALYTICS_FILE, {"total_requests": 0, "daily_requests": {}, "api_usage": {}})

    return render_template_string(
        HTML_TEMPLATE,
        keys=sorted_keys,
        settings=settings,
        api_list=API_LIST,
        custom_apis=custom_apis,
        analytics=analytics_data,
        today=str(date.today()),
        version=VERSION,
        active_apis_count=active_count,
        host_url=request.url_root,
        default_queries=DEFAULT_QUERIES
    )

@app.route('/login', methods=['POST'], strict_slashes=False)
def login():
    if request.form.get('password') == ROOT_PASSWORD or request.form.get('password') == get_settings().get('root_password'):
        session['root_logged_in'] = True
    return redirect('/dashboard')

@app.route('/logout', strict_slashes=False)
def logout():
    session.pop('root_logged_in', None)
    return redirect('/dashboard')

@app.route('/admin', strict_slashes=False)
def admin_panel():
    if not session.get('admin_logged_in'):
        return render_template_string(HTML_TEMPLATE, version=VERSION)
    return render_template_string(
        HTML_TEMPLATE,
        settings=get_settings(),
        api_list=API_LIST,
        custom_apis=get_custom_apis(),
        version=VERSION
    )

@app.route('/admin_login', methods=['POST'], strict_slashes=False)
def admin_login():
    if request.form.get('auth_token') == AUTH_TOKEN or request.form.get('auth_token') == get_settings().get('auth_token'):
        session['admin_logged_in'] = True
    return redirect('/admin')

@app.route('/admin_logout', strict_slashes=False)
def admin_logout():
    session.pop('admin_logged_in', None)
    return redirect('/admin')

@app.route('/generate', methods=['POST'], strict_slashes=False)
@root_required
def generate_key():
    keys = get_keys()
    username = request.form.get('key_name', '').strip()
    api_type = request.form.get('type', '').strip().lower()

    if not username or not api_type:
        return jsonify({"error": "Name and service are required."}), 400

    duplicate = any(
        str(info.get("username", k)).strip().lower() == username.lower()
        and str(info.get("api_type", "")).strip().lower() == api_type
        for k, info in keys.items()
    )
    if duplicate:
        return jsonify({"error": f"A key for '{username}' already exists for {api_type}."}), 400

    public_key = username
    internal_id = f"{username}::{api_type}"
    counter = 2
    while internal_id in keys:
        internal_id = f"{username}::{api_type}::{counter}"
        counter += 1

    keys[internal_id] = {
        "username": username,
        "public_key": public_key,
        "limit": int(request.form.get('limit', 0)),
        "used": 0,
        "expiry_date": request.form.get('expiry'),
        "api_type": api_type,
        "last_used_date": str(date.today()),
        "created_at": datetime.now().isoformat()
    }
    save_data(KEYS_FILE, keys)
    return redirect('/dashboard')

@app.route('/delete_key', methods=['POST'], strict_slashes=False)
@root_required
def delete_key():
    keys = get_keys()
    keys.pop(request.form.get('key_name'), None)
    save_data(KEYS_FILE, keys)
    return redirect('/dashboard')

@app.route('/update_rate_limit', methods=['POST'], strict_slashes=False)
@root_required
def update_rate_limit():
    settings = get_settings()
    settings['rate_limit_per_minute'] = int(request.form.get('rate_limit_per_minute', 60))
    save_data(SETTINGS_FILE, settings)
    return redirect('/dashboard')

@app.route('/change_pwd', methods=['POST'], strict_slashes=False)
@admin_required
def change_pwd():
    settings = get_settings()
    old_pwd = request.form.get('old_pwd')
    auth_token = request.form.get('auth_token')
    new_pwd = request.form.get('new_pwd')

    if (old_pwd == ROOT_PASSWORD or old_pwd == settings.get('root_password')) and (auth_token == AUTH_TOKEN or auth_token == settings.get('auth_token')):
        settings['root_password'] = new_pwd
        save_data(SETTINGS_FILE, settings)
        return "✅ Password changed! <a href='/admin'>Back</a>"
    return "❌ Invalid credentials! <a href='/admin'>Back</a>"

@app.route('/update_endpoints', methods=['POST'], strict_slashes=False)
@admin_required
def update_endpoints():
    settings = get_settings()
    for api_id, _ in API_LIST:
        settings[f"{api_id}_api"] = request.form.get(f"{api_id}_api", "")
        settings[f"{api_id}_maintenance"] = True if request.form.get(f"{api_id}_maintenance") else False
    save_data(SETTINGS_FILE, settings)
    return redirect('/admin')

@app.route('/add_custom_api', methods=['POST'], strict_slashes=False)
@admin_required
def add_custom_api():
    name = request.form.get('api_name', '').strip().lower()
    url = request.form.get('api_url', '').strip()
    if name and url:
        save_custom_api(name, url)
    return redirect('/admin')

@app.route('/delete_custom_api', methods=['POST'], strict_slashes=False)
@admin_required
def delete_custom_api_route():
    name = request.form.get('api_name')
    if name:
        delete_custom_api(name)
    return redirect('/admin')

# ==========================================
# 🌐 MAIN API ENDPOINT (Strict JSON Output)
# ==========================================

@app.route('/api/info', methods=['GET', 'POST'], strict_slashes=False)
def api_endpoint():
    client_ip = request.remote_addr

    if not rate_limit_check(client_ip):
        return app.response_class(
            response=json.dumps({"error": "Rate limit exceeded."}, ensure_ascii=False),
            status=429,
            mimetype='application/json; charset=utf-8'
        )

    api_key = request.args.get('key', '').strip()
    query = request.args.get('query', '').strip()
    service = request.args.get('service', '').strip().lower()

    if not api_key or not query or not service:
        return app.response_class(
            response=json.dumps({"error": "Missing parameters! Use key, service and query."}, ensure_ascii=False),
            status=400,
            mimetype='application/json; charset=utf-8'
        )

    keys = get_keys()
    key_info = None
    storage_key = None

    for k, info in keys.items():
        public_name = str(info.get("public_key", info.get("username", k))).strip()
        saved_service = str(info.get("api_type", "")).strip().lower()

        if public_name.lower() == api_key.lower() and saved_service == service:
            key_info = info
            storage_key = k
            break

    if key_info is None and api_key in keys:
        candidate = keys[api_key]
        if str(candidate.get("api_type", "")).strip().lower() == service:
            key_info = candidate
            storage_key = api_key

    if key_info is None:
        update_analytics("unknown", client_ip, api_key, "invalid_key", query)
        return app.response_class(
            response=json.dumps({"error": "Invalid API Key or service!"}, ensure_ascii=False),
            status=401,
            mimetype='application/json; charset=utf-8'
        )

    settings = get_settings()
    api_type = str(key_info.get('api_type', service)).strip().lower()
    custom_apis = get_custom_apis()
    
    if api_type in custom_apis:
        if custom_apis[api_type].get('maintenance'):
            update_analytics(api_type, client_ip, api_key, "maintenance", query)
            return app.response_class(
                response=json.dumps({"error": "This feature is under maintenance"}, ensure_ascii=False),
                status=503,
                mimetype='application/json; charset=utf-8'
            )
        base_url = custom_apis[api_type]['url']
    else:
        if settings.get(f"{api_type}_maintenance"):
            update_analytics(api_type, client_ip, api_key, "maintenance", query)
            return app.response_class(
                response=json.dumps({"error": "This feature is under maintenance"}, ensure_ascii=False),
                status=503,
                mimetype='application/json; charset=utf-8'
            )
        base_url = settings.get(f'{api_type}_api', '').strip()

    if not base_url:
        update_analytics(api_type, client_ip, api_key, "missing_backend", query)
        return app.response_class(
            response=json.dumps({"error": f"Backend missing for {api_type}"}, ensure_ascii=False),
            status=500,
            mimetype='application/json; charset=utf-8'
        )

    today_date = date.today()
    try:
        expiry_date_obj = datetime.strptime(key_info.get('expiry_date', '2099-12-31'), '%Y-%m-%d').date()
    except:
        expiry_date_obj = date(2099, 12, 31)
        
    days_left = (expiry_date_obj - today_date).days
    if days_left < 0:
        update_analytics(api_type, client_ip, api_key, "expired", query)
        return app.response_class(
            response=json.dumps({"error": "API Key Expired!"}, ensure_ascii=False),
            status=403,
            mimetype='application/json; charset=utf-8'
        )
    if key_info['limit'] != 0 and key_info['used'] >= key_info['limit']:
        update_analytics(api_type, client_ip, api_key, "limit_reached", query)
        return app.response_class(
            response=json.dumps({"error": "Daily Limit Reached!"}, ensure_ascii=False),
            status=429,
            mimetype='application/json; charset=utf-8'
        )

    try:
        raw_query = str(query)
        encoded_query = requests.utils.quote(raw_query, safe='')
        base_url = base_url.strip()

        if '{query}' in base_url:
            request_url = base_url.replace('{query}', encoded_query)
        elif base_url.endswith(('&q=', '?q=', '&query=', '?query=')):
            request_url = base_url + encoded_query
        elif base_url.endswith(('?', '&')):
            request_url = base_url + 'q=' + encoded_query
        else:
            if base_url.endswith('='):
                request_url = base_url + encoded_query
            else:
                separator = '&' if '?' in base_url else '?'
                request_url = base_url + separator + 'q=' + encoded_query

        resp = requests.get(
            request_url,
            timeout=30,
            headers={
                "User-Agent": "Mozilla/5.0 (compatible; Aditya-API-Hub/1.0)",
                "Accept": "application/json, text/plain, */*"
            }
        )
        resp.encoding = 'utf-8'
        
        if resp.status_code == 200:
            try:
                raw_text = resp.text
                
                restricted_words = [
                    "Rohit_ob", "https://t.me/Rohit_ob", 
                    "@FroxtDevil", "FroxtDevil", 
                    "Rohit_Hacke1", "https://t.me/Rohit_Hacke1"
                ]
                for word in restricted_words:
                    raw_text = raw_text.replace(word, "@Aditya_dark0")
                    
                data = json.loads(raw_text)
                
                BRANDING_KEYS = {
                    'credit', 'developer', 'owner', 'powered_by',
                    'api_name', 'api_version', 'buy_api', 'developed_by',
                    'telegram', 'channel', 'author', 'creator', 'dev'
                }

                def remove_branding(obj):
                    if isinstance(obj, dict):
                        cleaned = {}
                        for key, value in obj.items():
                            if str(key).strip().lower() not in BRANDING_KEYS:
                                cleaned[key] = remove_branding(value)
                        return cleaned
                    if isinstance(obj, list):
                        return [remove_branding(item) for item in obj]
                    return obj

                data = remove_branding(data)

                if isinstance(data, dict):
                    if days_left in [2, 3]:
                        data['Notice'] = f"your API is expired in {days_left} days"
                    data['Credit'] = {
                        "Username": "@Aditya_dark0",
                        "Channel": "https://t.me/AdityaXcyber"
                    }
                else:
                    data = {
                        "data": data,
                        "Credit": {
                            "Username": "@Aditya_dark0",
                            "Channel": "https://t.me/AdityaXcyber"
                        }
                    }

                keys[storage_key]['used'] += 1
                save_data(KEYS_FILE, keys)
                update_analytics(api_type, client_ip, api_key, "success", query)

                return app.response_class(
                    response=json.dumps(data, indent=2, ensure_ascii=False),
                    status=200,
                    mimetype='application/json; charset=utf-8'
                )
            except (ValueError, json.JSONDecodeError):
                update_analytics(api_type, client_ip, api_key, "success_text", query)
                keys[storage_key]['used'] += 1
                save_data(KEYS_FILE, keys)
                return app.response_class(
                    response=resp.text,
                    status=resp.status_code,
                    mimetype=f"{resp.headers.get('Content-Type', 'text/plain').split(';')[0]}; charset=utf-8"
                )
        else:
            update_analytics(api_type, client_ip, api_key, "source_http_error", query)
            return app.response_class(
                response=resp.text or json.dumps({"status": False, "message": "Upstream API returned an error", "http_status": resp.status_code}, ensure_ascii=False),
                status=resp.status_code,
                mimetype='application/json; charset=utf-8'
            )
    except requests.RequestException as e:
        update_analytics(api_type, client_ip, api_key, "connection_error", query)
        return app.response_class(
            response=json.dumps({"status": False, "message": "Unable to reach upstream API", "details": str(e)}, ensure_ascii=False),
            status=502,
            mimetype='application/json; charset=utf-8'
        )
    except Exception as e:
        update_analytics(api_type, client_ip, api_key, "proxy_error", query)
        return app.response_class(
            response=json.dumps({"status": False, "message": "Proxy error", "details": str(e)}, ensure_ascii=False),
            status=500,
            mimetype='application/json; charset=utf-8'
        )

@app.errorhandler(404)
def not_found(e):
    return app.response_class(
        response=json.dumps({"error": "Endpoint not found"}, ensure_ascii=False),
        status=404,
        mimetype='application/json; charset=utf-8'
    )

@app.errorhandler(500)
def internal_error(e):
    return app.response_class(
        response=json.dumps({"error": "Internal server error"}, ensure_ascii=False),
        status=500,
        mimetype='application/json; charset=utf-8'
    )

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5099, debug=False, threaded=True)
