
import os
import time
import sqlite3
import json
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from google import genai
from google.genai import types

app = Flask(__name__)
CORS(app)

# CONFIGURATION
GEMINI_API_KEY ="AQ.Ab8RN6L38tUETkvV4SAi0rlRfhjOSsCvSlmuBI8BhNbiU_pqiQ"
ADMIN_KEY = os.environ.get("ADMIN_KEY", "MyFallbackKey2026!")
client = genai.Client(api_key=GEMINI_API_KEY, http_options={'api_version': 'v1alpha'})

# DATABASE SETUP
def init_db():
    conn = sqlite3.connect('aicoach.db')
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

# === HELPER FUNCTIONS ===

def get_db():
    conn = sqlite3.connect('aicoach.db')
    conn.row_factory = sqlite3.Row
    return conn

def generate_system_prompt(name, expertise, description, user_context=None, user_values=None):
    """Generate a comprehensive system prompt for the coach using Gemini 3"""
    
    prompt = f"""You are an expert AI coach creation system. Generate a detailed, effective system prompt for an AI coach with these specifications:

Coach Name: {name}
Expertise: {expertise}
Description: {description}

The system prompt should:
1. Define the coach's personality and coaching style
2. Specify their area of expertise and how they apply it
3. Include specific techniques and frameworks they use
4. Define how they structure coaching conversations
5. Specify the type of questions they ask and insights they provide
6. Include guidelines for empathy, encouragement, and accountability

Make it actionable, specific, and aligned with best coaching practices.

Return ONLY the system prompt text, no preamble."""

    response = client.models.generate_content(
        model="gemini-3-flash-preview",
        contents=prompt,
        config=types.GenerateContentConfig(
            thinking_config=types.ThinkingConfig(thinking_level="medium"),
            temperature=1.0
        )
    )
    
    system_prompt = response.text.strip()
    
    # Add user context if available
    if user_context or user_values:
        context_addition = "\n\nIMPORTANT USER CONTEXT:\n"
        if user_context:
            context_addition += f"About the user: {user_context}\n"
        if user_values:
            context_addition += f"User's values: {user_values}\n"
        context_addition += "\nUse this context to personalize your coaching and make it more relevant to the user's situation."
        system_prompt += context_addition
    
    return system_prompt

# === AUTH ROUTES ===

@app.route('/auth/register', methods=['POST'])
def register():
    data = request.json
    email = data.get('email')
    password = generate_password_hash(data.get('password'))
    
    try:
        conn = get_db()
        c = conn.cursor()
        c.execute("INSERT INTO users (email, password) VALUES (?, ?)", (email, password))
        conn.commit()
        
        user_id = c.lastrowid
        user = c.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        
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
    finally:
        conn.close()

@app.route('/auth/login', methods=['POST'])
def login():
    data = request.json
    conn = get_db()
    c = conn.cursor()
    user = c.execute("SELECT * FROM users WHERE email = ?", (data.get('email'),)).fetchone()
    conn.close()
    
    if user and check_password_hash(user['password'], data.get('password')):
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

# === USER ROUTES ===

@app.route('/user/<user_id>/profile', methods=['GET'])
def get_profile(user_id):
    conn = get_db()
    user = conn.cursor().execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
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
    data = request.json
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

# === COACH ROUTES ===

@app.route('/coaches', methods=['GET'])
def get_coaches():
    public_only = request.args.get('public_only', 'true').lower() == 'true'
    
    conn = get_db()
    c = conn.cursor()
    
    if public_only:
        coaches = c.execute(
            "SELECT * FROM coaches WHERE is_public = 1 ORDER BY share_count DESC, created_at DESC"
        ).fetchall()
    else:
        coaches = c.execute(
            "SELECT * FROM coaches ORDER BY created_at DESC"
        ).fetchall()
    
    conn.close()
    
    coach_list = []
    for coach in coaches:
        coach_list.append({
            'id': str(coach['id']),
            'name': coach['name'],
            'description': coach['description'],
            'expertise': coach['expertise'],
            'system_prompt': coach['system_prompt'],
            'creator_id': str(coach['creator_id']),
            'is_public': bool(coach['is_public']),
            'share_count': coach['share_count'],
            'created_at': coach['created_at']
        })
    
    return jsonify({'success': True, 'coaches': coach_list})

@app.route('/coaches/create', methods=['POST'])
def create_coach():
    data = request.json
    user_id = data.get('user_id')
    name = data.get('name')
    description = data.get('description')
    expertise = data.get('expertise')
    is_public = data.get('is_public', True)
    
    # Get user context for personalization
    conn = get_db()
    c = conn.cursor()
    user = c.execute("SELECT context_text, values_text FROM users WHERE id = ?", (user_id,)).fetchone()
    
    # Generate system prompt using Gemini 3
    try:
        system_prompt = generate_system_prompt(
            name, 
            expertise, 
            description,
            user['context_text'] if user else None,
            user['values_text'] if user else None
        )
        
        c.execute(
            """INSERT INTO coaches (name, description, expertise, system_prompt, creator_id, is_public)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (name, description, expertise, system_prompt, user_id, 1 if is_public else 0)
        )
        conn.commit()
        coach_id = c.lastrowid
        
        return jsonify({
            'success': True, 
            'message': 'Coach created',
            'coach_id': str(coach_id)
        })
    except Exception as e:
        return jsonify({'success': False, 'message': f'Failed to create coach: {str(e)}'}), 500
    finally:
        conn.close()

@app.route('/coaches/<coach_id>/share', methods=['POST'])
def share_coach(coach_id):
    conn = get_db()
    c = conn.cursor()
    c.execute("UPDATE coaches SET share_count = share_count + 1 WHERE id = ?", (coach_id,))
    conn.commit()
    conn.close()
    
    return jsonify({'success': True, 'message': 'Share count updated'})

# === CHAT ROUTES ===

@app.route('/chat/send', methods=['POST'])
def send_message():
    data = request.json
    user_id = data.get('user_id')
    coach_id = data.get('coach_id')
    message = data.get('message')
    history = data.get('history', [])
    
    conn = get_db()
    c = conn.cursor()
    
    # Get coach details
    coach = c.execute("SELECT * FROM coaches WHERE id = ?", (coach_id,)).fetchone()
    if not coach:
        conn.close()
        return jsonify({'success': False, 'message': 'Coach not found'}), 404
    
    # Get user context
    user = c.execute("SELECT context_text, values_text FROM users WHERE id = ?", (user_id,)).fetchone()
    
    try:
        # Build conversation for Gemini
        contents = []
        
        # Add system instructions as first user message with context
        system_message = coach['system_prompt']
        if user and (user['context_text'] or user['values_text']):
            system_message += "\n\nREMEMBER - User Context:\n"
            if user['context_text']:
                system_message += f"About them: {user['context_text']}\n"
            if user['values_text']:
                system_message += f"Their values: {user['values_text']}\n"
        
        # Add history
        for msg in history:
            if msg['role'] == 'user':
                contents.append(types.Content(
                    role='user',
                    parts=[types.Part(text=msg['content'])]
                ))
            elif msg['role'] == 'assistant':
                contents.append(types.Content(
                    role='model',
                    parts=[types.Part(text=msg['content'])]
                ))
        
        # Add current message
        contents.append(types.Content(
            role='user',
            parts=[types.Part(text=message)]
        ))
        
        # Generate response with Gemini 3 Flash + Thinking + Search Grounding
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_message,
                thinking_config=types.ThinkingConfig(thinking_level="high"),
                tools=[{"google_search": {}}],  # Enable search grounding
                temperature=1.0
            )
        )
        
        assistant_message = response.text
        
        # Save conversation
        all_messages = history + [
            {'role': 'user', 'content': message, 'timestamp': datetime.now().isoformat()},
            {'role': 'assistant', 'content': assistant_message, 'timestamp': datetime.now().isoformat()}
        ]
        
        # Check if conversation exists
        conversation = c.execute(
            "SELECT id FROM conversations WHERE user_id = ? AND coach_id = ?",
            (user_id, coach_id)
        ).fetchone()
        
        if conversation:
            c.execute(
                "UPDATE conversations SET messages = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                (json.dumps(all_messages), conversation['id'])
            )
        else:
            c.execute(
                "INSERT INTO conversations (user_id, coach_id, messages) VALUES (?, ?, ?)",
                (user_id, coach_id, json.dumps(all_messages))
            )
        
        conn.commit()
        
        return jsonify({
            'success': True,
            'message': assistant_message
        })
        
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500
    finally:
        conn.close()

# === HEALTH CHECK ===

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'service': 'AI Coach API'
    })

# === SEED DEFAULT COACHES ===

def seed_default_coaches():
    """Create some default public coaches for users to discover"""
    conn = get_db()
    c = conn.cursor()
    
    # Check if we already have coaches
    existing = c.execute("SELECT COUNT(*) as count FROM coaches").fetchone()
    if existing['count'] > 0:
        conn.close()
        return
    
    # Create a system user
    try:
        c.execute("INSERT INTO users (email, password, tier) VALUES (?, ?, ?)",
                 ('system@aicoach.app', generate_password_hash('system123'), 'premium'))
        system_user_id = c.lastrowid
    except:
        system_user_id = c.execute("SELECT id FROM users WHERE email = ?", 
                                   ('system@aicoach.app',)).fetchone()['id']
    
    default_coaches = [
        {
            'name': 'Productivity Pro',
            'expertise': 'Time Management & Productivity',
            'description': 'Helps you build systems, prioritize effectively, and get more done with less stress.',
        },
        {
            'name': 'Career Navigator',
            'expertise': 'Career Development & Strategy',
            'description': 'Guides you through career transitions, skill development, and professional growth.',
        },
        {
            'name': 'Mindful Mentor',
            'expertise': 'Mindfulness & Well-being',
            'description': 'Supports your mental health journey with practical mindfulness techniques and self-care strategies.',
        },
        {
            'name': 'Goal Achiever',
            'expertise': 'Goal Setting & Achievement',
            'description': 'Helps you set meaningful goals, create action plans, and stay accountable.',
        },
        {
            'name': 'Communication Coach',
            'expertise': 'Communication & Relationships',
            'description': 'Improves your interpersonal skills, conflict resolution, and leadership communication.',
        }
    ]
    
    for coach_data in default_coaches:
        try:
            system_prompt = generate_system_prompt(
                coach_data['name'],
                coach_data['expertise'],
                coach_data['description']
            )
            
            c.execute(
                """INSERT INTO coaches (name, description, expertise, system_prompt, creator_id, is_public, share_count)
                   VALUES (?, ?, ?, ?, ?, 1, ?)""",
                (coach_data['name'], coach_data['description'], coach_data['expertise'], 
                 system_prompt, system_user_id, 0)
            )
        except Exception as e:
            print(f"Error creating default coach {coach_data['name']}: {e}")
    
    conn.commit()
    conn.close()
    print("Default coaches seeded successfully!")

if __name__ == '__main__':
    # Seed default coaches on startup
    seed_default_coaches()
    
    # Run the app
    app.run(host='0.0.0.0', debug=True, port=5000)