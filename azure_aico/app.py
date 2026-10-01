import os
import time
import sqlite3
import json
import requests
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
CORS(app)

# ==========================================
# CONFIGURATION & ENVIRONMENT
# ==========================================
DB_PATH = 'aicoach.db'
ADMIN_KEY = os.environ.get("ADMIN_KEY", "MyFallbackKey2026!")

# Microsoft Foundry Configuration (gpt-5.4-nano)
AI_ENDPOINT = os.environ.get(
    "AI_ENDPOINT",
    "https://opejeremiah-2939-resource.services.ai.azure.com/openai/v1/chat/completions"
)
AI_KEY = os.environ.get(
    "AI_KEY",
    "5rU3LmcHk8WjNdiyJ30vbmsTNGuHhFfe9Ln5hXz6DtkrqOYWSB7IJQQJ99CEAC1i4TkXJ3w3AAAAACOG5h7l"
)
AI_MODEL = "gpt-5.4-nano"

# ==========================================
# BULLETPROOF DATABASE CONNECTION
# ==========================================
def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=30.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    return conn

def init_db():
    conn = get_db()
    c = conn.cursor()
    
    # Users table
    c.execute('''CREATE TABLE IF NOT EXISTS users 
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                  email TEXT UNIQUE, 
                  password TEXT, 
                  trials INTEGER DEFAULT 5, 
                  tier TEXT DEFAULT 'free',
                  coach_creation_credits INTEGER DEFAULT 0,
                  chat_credits INTEGER DEFAULT 0,
                  context_text TEXT,
                  values_text TEXT,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
    
    # Coaches table
    c.execute('''CREATE TABLE IF NOT EXISTS coaches
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  name TEXT NOT NULL,
                  description TEXT NOT NULL,
                  expertise TEXT NOT NULL,
                  system_prompt TEXT NOT NULL,
                  creator_id INTEGER NOT NULL,
                  is_public INTEGER DEFAULT 1,
                  share_count INTEGER DEFAULT 0,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  FOREIGN KEY (creator_id) REFERENCES users(id))''')
    
    # Conversations table
    c.execute('''CREATE TABLE IF NOT EXISTS conversations
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  user_id INTEGER NOT NULL,
                  coach_id INTEGER NOT NULL,
                  messages TEXT NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  FOREIGN KEY (user_id) REFERENCES users(id),
                  FOREIGN KEY (coach_id) REFERENCES coaches(id))''')
    
    conn.commit()
    conn.close()

init_db()

# ==========================================
# AI CALLER (Microsoft Foundry gpt-5.4-nano)
# ==========================================
def call_gpt_nano(prompt, system_instruction="You are an expert AI mentor creation and coaching engine."):
    headers = {
        "Content-Type": "application/json",
        "api-key": AI_KEY,
        "Authorization": f"Bearer {AI_KEY}"
    }

    target_url = AI_ENDPOINT
    if target_url.endswith("/responses"):
        target_url = target_url.replace("/responses", "/chat/completions")

    payload = {
        "model": AI_MODEL,
        "messages": [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.7
    }

    try:
        res = requests.post(target_url, headers=headers, json=payload, timeout=25)
        if res.status_code == 200:
            return res.json()['choices'][0]['message']['content'].strip()
        else:
            return "I am here to guide your progress. Let's focus on your top priority right now."
    except Exception as e:
        return f"Focus on steady progress today. (Notice: {str(e)})"

def generate_system_prompt(name, expertise, description, user_context=None, user_values=None):
    prompt = f"""
    Generate an actionable, tailored system prompt for an AI Coach:
    Coach Name: {name}
    Expertise: {expertise}
    Approach: {description}
    Requirements:
    1. Define personality and coaching frameworks
    2. Specify questions asked and empathy guidelines
    3. Return ONLY the system prompt text with no preambles.
    """
    
    system_prompt = call_gpt_nano(prompt)
    
    if user_context or user_values:
        system_prompt += f"\n\nUSER CONTEXT:\nAbout user: {user_context or 'None'}\nValues: {user_values or 'None'}\nUse this context to personalize conversations."
        
    return system_prompt

# ==========================================
# AUTH ROUTES
# ==========================================
@app.route('/auth/register', methods=['POST'])
def register():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')
    
    if not email or not password:
        return jsonify({'success': False, 'message': 'Email and password required'}), 400

    hashed = generate_password_hash(password)
    
    try:
        conn = get_db()
        c = conn.cursor()
        c.execute("INSERT INTO users (email, password) VALUES (?, ?)", (email, hashed))
        user_id = c.lastrowid
        conn.commit()
        
        user = c.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        conn.close()
        
        return jsonify({
            'success': True, 
            'message': 'User registered',
            'user': {
                'user_id': str(user['id']), 
                'email': user['email'], 
                'trials_remaining': user['trials'],
                'tier': user['tier'],
                'coach_creation_credits': user['coach_creation_credits'],
                'chat_credits': user['chat_credits'],
                'context_text': user['context_text'],
                'values_text': user['values_text']
            }
        })
    except sqlite3.IntegrityError:
        return jsonify({'success': False, 'message': 'User already exists'}), 400
    except Exception as e:
        return jsonify({'success': False, 'message': f'Registration failed: {str(e)}'}), 500

@app.route('/auth/login', methods=['POST'])
def login():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')
    
    conn = get_db()
    c = conn.cursor()
    user = c.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    conn.close()
    
    if user and check_password_hash(user['password'], password):
        return jsonify({
            'success': True, 
            'user': {
                'user_id': str(user['id']), 
                'email': user['email'], 
                'trials_remaining': user['trials'],
                'tier': user['tier'],
                'coach_creation_credits': user['coach_creation_credits'],
                'chat_credits': user['chat_credits'],
                'context_text': user['context_text'],
                'values_text': user['values_text']
            }
        })
    return jsonify({'success': False, 'message': 'Invalid credentials'}), 401

# ==========================================
# USER PROFILE & CONTEXT
# ==========================================
@app.route('/user/<user_id>/profile', methods=['GET'])
def get_profile(user_id):
    conn = get_db()
    c = conn.cursor()
    user = c.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    conn.close()
    
    if user:
        return jsonify({
            'success': True,
            'user': {
                'user_id': str(user['id']), 
                'email': user['email'], 
                'trials_remaining': user['trials'],
                'tier': user['tier'],
                'coach_creation_credits': user['coach_creation_credits'],
                'chat_credits': user['chat_credits'],
                'context_text': user['context_text'],
                'values_text': user['values_text']
            }
        })
    return jsonify({'success': False, 'message': 'User not found'}), 404

@app.route('/user/<user_id>/context', methods=['POST'])
def update_context(user_id):
    data = request.json or {}
    context_text = data.get('context_text')
    values_text = data.get('values_text')
    
    conn = get_db()
    c = conn.cursor()
    c.execute(
        "UPDATE users SET context_text = ?, values_text = ? WHERE id = ?",
        (context_text, values_text, user_id)
    )
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Context updated'})

# ==========================================
# COACHES & CHAT SESSIONS
# ==========================================
@app.route('/coaches', methods=['GET'])
def get_coaches():
    public_only = request.args.get('public_only', 'true').lower() == 'true'
    conn = get_db()
    c = conn.cursor()
    
    if public_only:
        coaches = c.execute("SELECT * FROM coaches WHERE is_public = 1 ORDER BY share_count DESC, id DESC").fetchall()
    else:
        coaches = c.execute("SELECT * FROM coaches ORDER BY id DESC").fetchall()
    conn.close()
    
    return jsonify({
        'success': True,
        'coaches': [
            {
                'id': str(coach['id']),
                'name': coach['name'],
                'description': coach['description'],
                'expertise': coach['expertise'],
                'system_prompt': coach['system_prompt'],
                'creator_id': str(coach['creator_id']),
                'is_public': bool(coach['is_public']),
                'share_count': coach['share_count'],
                'created_at': coach['created_at']
            } for coach in coaches
        ]
    })

@app.route('/coaches/create', methods=['POST'])
def create_coach():
    data = request.json or {}
    user_id = data.get('user_id')
    name = data.get('name', 'AI Mentor')
    description = data.get('description', '')
    expertise = data.get('expertise', 'General Coaching')
    is_public = data.get('is_public', True)
    
    conn = get_db()
    c = conn.cursor()
    user = c.execute("SELECT context_text, values_text FROM users WHERE id = ?", (user_id,)).fetchone()
    
    try:
        system_prompt = generate_system_prompt(
            name, expertise, description,
            user['context_text'] if user else None,
            user['values_text'] if user else None
        )
        
        c.execute("""
            INSERT INTO coaches (name, description, expertise, system_prompt, creator_id, is_public)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (name, description, expertise, system_prompt, user_id, 1 if is_public else 0))
        conn.commit()
        coach_id = c.lastrowid
        conn.close()
        
        return jsonify({'success': True, 'message': 'Coach created', 'coach_id': str(coach_id)})
    except Exception as e:
        conn.close()
        return jsonify({'success': False, 'message': f'Failed to create coach: {str(e)}'}), 500

@app.route('/coaches/<coach_id>/share', methods=['POST'])
def share_coach(coach_id):
    conn = get_db()
    c = conn.cursor()
    c.execute("UPDATE coaches SET share_count = share_count + 1 WHERE id = ?", (coach_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Share count updated'})

@app.route('/chat/send', methods=['POST'])
def send_message():
    data = request.json or {}
    user_id = data.get('user_id')
    coach_id = data.get('coach_id')
    message = data.get('message', '')
    history = data.get('history', [])
    
    conn = get_db()
    c = conn.cursor()
    coach = c.execute("SELECT * FROM coaches WHERE id = ?", (coach_id,)).fetchone()
    if not coach:
        conn.close()
        return jsonify({'success': False, 'message': 'Coach not found'}), 404
        
    user = c.execute("SELECT context_text, values_text FROM users WHERE id = ?", (user_id,)).fetchone()
    
    system_inst = coach['system_prompt']
    if user and (user['context_text'] or user['values_text']):
        system_inst += f"\nUser Background: {user['context_text']}\nValues: {user['values_text']}"
        
    conversation_context = "\n".join([f"{m.get('role', 'user')}: {m.get('content', '')}" for m in history[-6:]])
    full_prompt = f"Previous conversation:\n{conversation_context}\n\nUser: {message}\nCoach:"
    
    assistant_reply = call_gpt_nano(full_prompt, system_instruction=system_inst)
    
    all_messages = history + [
        {'role': 'user', 'content': message, 'timestamp': datetime.utcnow().isoformat()},
        {'role': 'assistant', 'content': assistant_reply, 'timestamp': datetime.utcnow().isoformat()}
    ]
    
    conv = c.execute("SELECT id FROM conversations WHERE user_id = ? AND coach_id = ?", (user_id, coach_id)).fetchone()
    if conv:
        c.execute("UPDATE conversations SET messages = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                  (json.dumps(all_messages), conv['id']))
    else:
        c.execute("INSERT INTO conversations (user_id, coach_id, messages) VALUES (?, ?, ?)",
                  (user_id, coach_id, json.dumps(all_messages)))
                  
    conn.commit()
    conn.close()
    
    return jsonify({'success': True, 'message': assistant_reply})

# ==========================================
# ADMIN, POLICIES & HEALTH
# ==========================================
@app.route('/admin')
def admin_dashboard():
    if request.args.get('key') != ADMIN_KEY:
        return jsonify({'error': 'Unauthorized'}), 401

    conn = get_db()
    c = conn.cursor()
    users = c.execute("SELECT id, email, tier, trials, created_at FROM users ORDER BY id DESC").fetchall()
    conn.close()

    rows = "".join([f"""
        <tr>
            <td style='padding:12px; border-bottom:1px solid #eee;'>{u['id']}</td>
            <td style='padding:12px; border-bottom:1px solid #eee; font-weight:600;'>{u['email']}</td>
            <td style='padding:12px; border-bottom:1px solid #eee;'>
                <span style='background:#EEF2FF; color:#4F46E5; padding:4px 10px; border-radius:12px; font-size:12px; font-weight:bold;'>
                    {(u['tier'] or 'FREE').upper()}
                </span>
            </td>
            <td style='padding:12px; border-bottom:1px solid #eee;'>{u['trials']}</td>
            <td style='padding:12px; border-bottom:1px solid #eee; color:#64748b;'>{u['created_at']}</td>
        </tr>
    """ for u in users])

    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>AI Coach - Admin Dashboard</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body {{ font-family: -apple-system, sans-serif; background: #f8fafc; padding: 30px; }}
            .card {{ background: white; border-radius: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); max-width: 800px; margin: auto; overflow: hidden; }}
            .header {{ background: #4F46E5; color: white; padding: 24px; }}
            table {{ width: 100%; border-collapse: collapse; text-align: left; }}
            th {{ background: #f1f5f9; padding: 14px; font-size: 13px; color: #475569; }}
        </style>
    </head>
    <body>
        <div class="card">
            <div class="header">
                <h2 style="margin:0;">AI Coach - Registered Users ({len(users)})</h2>
                <p style="margin:6px 0 0; opacity:0.85; font-size:13px;">Engine: Microsoft Foundry ({AI_MODEL}) | DB: SQLite (WAL Active)</p>
            </div>
            <table>
                <thead>
                    <tr><th>ID</th><th>Email</th><th>Tier</th><th>Trials Left</th><th>Joined</th></tr>
                </thead>
                <tbody>
                    {rows if rows else "<tr><td colspan='5' style='padding:24px; text-align:center;'>No users registered yet.</td></tr>"}
                </tbody>
            </table>
        </div>
    </body>
    </html>
    """

@app.route('/delete-account')
def delete_account_info():
    return """
    <!DOCTYPE html>
    <html>
    <head><meta charset="UTF-8"><title>AI Coach - Delete Account</title></head>
    <body style="font-family:sans-serif; padding:40px; max-width:600px; margin:auto; line-height:1.6; color:#222;">
        <h2>AI Coach - Account & Data Deletion</h2>
        <p>To delete your AI Coach account, custom coach profiles, and all associated chat data, please send an email to <b>support@presentmeapp.xyz</b> with the subject 'Delete Account'.</p>
        <p>Your request will be processed, and all stored personal data will be permanently removed within 30 days.</p>
    </body>
    </html>
    """

@app.route("/privacy")
def privacy_policy():
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Privacy Policy - AI Coach</title>
        <style>
            body { font-family: -apple-system, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 30px; color: #222; background: #f8fafc; }
            h1, h2 { color: #4F46E5; }
            .card { background: white; padding: 30px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>Privacy Policy for AI Coach</h1>
            <p><strong>Effective Date:</strong> September 2026</p>
            <p>AI Coach ("we", "our", or "us") provides personalized AI mentoring and coaching tools. This Privacy Policy outlines our data handling practices.</p>
            <h2>1. Information We Collect</h2>
            <p>• <strong>Personal Info:</strong> Email address for account creation, authentication, and session persistence.</p>
            <p>• <strong>Coaching Context:</strong> User values and custom mentor prompts stored securely to personalize your sessions.</p>
            <p>• <strong>Purchase Data:</strong> Transaction histories to manage subscription tiers and credit packs via Google Play Billing and RevenueCat. We never store raw credit card numbers.</p>
            <h2>2. Third-Party Services</h2>
            <p>We utilize trusted providers including Google Play Services (core distribution/billing), Microsoft Foundry AI (mentor intelligence), and RevenueCat (subscription management).</p>
            <h2>3. Data Deletion & Contact</h2>
            <p>To request deletion of your account and all stored data, contact us at <strong>support@presentmeapp.xyz</strong>.</p>
        </div>
    </body>
    </html>
    """

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'service': 'AI Coach API',
        'engine': AI_MODEL,
        'timestamp': datetime.utcnow().isoformat()
    })

def seed_default_coaches():
    conn = get_db()
    c = conn.cursor()
    existing = c.execute("SELECT COUNT(*) as count FROM coaches").fetchone()
    if existing['count'] > 0:
        conn.close()
        return
    
    try:
        c.execute("INSERT INTO users (email, password, tier) VALUES (?, ?, ?)",
                 ('system@aicoach.app', generate_password_hash('system123'), 'premium'))
        system_user_id = c.lastrowid
    except:
        system_user_id = c.execute("SELECT id FROM users WHERE email = ?", ('system@aicoach.app',)).fetchone()['id']
    
    default_coaches = [
        {'name': 'Productivity Pro', 'expertise': 'Time Management', 'description': 'Helps you build systems and focus.'},
        {'name': 'Career Navigator', 'expertise': 'Career Growth', 'description': 'Guides you through transitions.'},
        {'name': 'Mindful Mentor', 'expertise': 'Mindfulness & Wellbeing', 'description': 'Supports mental clarity.'}
    ]
    for d in default_coaches:
        try:
            sys_p = f"You are {d['name']}, expert in {d['expertise']}. {d['description']}"
            c.execute("INSERT INTO coaches (name, description, expertise, system_prompt, creator_id, is_public, share_count) VALUES (?, ?, ?, ?, ?, 1, 0)",
                      (d['name'], d['description'], d['expertise'], sys_p, system_user_id))
        except Exception:
            pass
    conn.commit()
    conn.close()

if __name__ == '__main__':
    seed_default_coaches()
    app.run(host='0.0.0.0', debug=True, port=5000)