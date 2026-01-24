#!/usr/bin/env python3
"""
Aurora Session Insights Updater
Extracts new session insights and updates the website
"""

import os
import sys
import subprocess
import json
import re
from datetime import datetime
from pathlib import Path

# Configuration
INSIGHTS_FILE = Path("/home/elijah/aurora/aurora_memory/session_insights.json")
WEBSITE_REPO = Path("/home/elijah/aurora_ai")
WEBSITE_REPO_URL = "https://github.com/elijahsylar/aurora_ai.git"
LAST_UPDATE_FILE = Path("/home/elijah/.aurora_last_insight_update")


def ensure_repo_exists(repo_path, repo_url):
    """Clone repo if it doesn't exist"""
    if not repo_path.exists():
        print(f"📦 Cloning {repo_url}...")
        subprocess.run(['git', 'clone', repo_url, str(repo_path)], check=True)
    else:
        print(f"✓ Repository exists at {repo_path}")


def get_last_update_date():
    """Get the date of the last insights update"""
    if LAST_UPDATE_FILE.exists():
        with open(LAST_UPDATE_FILE, 'r') as f:
            return f.read().strip()
    return None


def save_last_update_date(date_str):
    """Save the current update date"""
    with open(LAST_UPDATE_FILE, 'w') as f:
        f.write(date_str)


def load_session_insights():
    """Load all session insights"""
    if not INSIGHTS_FILE.exists():
        print(f"❌ Session insights file not found: {INSIGHTS_FILE}")
        sys.exit(1)
    
    with open(INSIGHTS_FILE, 'r') as f:
        return json.load(f)


def filter_new_sessions(all_insights, last_update_date):
    """Filter sessions since last update"""
    if not last_update_date:
        # First run - get last 10 days of sessions
        print("📅 First run - extracting last 10 days of sessions...")
        cutoff_date = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        cutoff_date = cutoff_date.replace(day=cutoff_date.day - 10)
    else:
        cutoff_date = datetime.strptime(last_update_date, "%Y-%m-%d")
        print(f"📅 Extracting sessions since: {last_update_date}")
    
    new_sessions = {}
    for session_id, session_data in all_insights.items():
        try:
            # Parse session date from ID (format: session_YYYYMMDD_HHMMSS)
            date_match = re.search(r'(\d{8})', session_id)
            if date_match:
                session_date = datetime.strptime(date_match.group(1), "%Y%m%d")
                if session_date >= cutoff_date:
                    new_sessions[session_id] = session_data
        except:
            continue
    
    return new_sessions


def calculate_stats(sessions):
    """Calculate aggregate statistics from sessions"""
    if not sessions:
        return None
    
    total_pixels = 0
    total_steps = 0
    emotions = {}
    top_mastery = {}
    patterns_discovered = set()
    
    for session_id, session in sessions.items():
        # Get pixels drawn
        if 'session_statistics' in session:
            stats = session['session_statistics']
            total_pixels += stats.get('total_pixels_drawn', 0)
            total_steps += stats.get('total_steps', 0)
        
        # Get emotional states
        if 'creative_discoveries' in session:
            emotional_exp = session['creative_discoveries'].get('emotional_expressions', {})
            for emotion, data in emotional_exp.items():
                emotions[emotion] = emotions.get(emotion, 0) + 1
        
        # Get mastery progression
        if 'learning_progression' in session and 'mastery_levels' in session['learning_progression']:
            for skill, level in session['learning_progression']['mastery_levels'].items():
                if level in ['advanced', 'expert', 'master']:
                    top_mastery[skill] = level
        
        # Get patterns
        if 'creative_discoveries' in session:
            new_patterns = session['creative_discoveries'].get('new_patterns', [])
            patterns_discovered.update(new_patterns)
    
    # Get dominant emotion
    dominant_emotion = max(emotions.items(), key=lambda x: x[1])[0] if emotions else "Creative"
    
    # Get top skill
    top_skill = max(top_mastery.items(), key=lambda x: ['novice','beginner','intermediate','advanced','expert','master'].index(x[1]))[0] if top_mastery else "Exploration"
    
    return {
        'total_pixels': total_pixels,
        'total_steps': total_steps,
        'session_count': len(sessions),
        'dominant_emotion': dominant_emotion.capitalize(),
        'top_skill': top_skill.replace('_', ' ').title(),
        'unique_patterns': len(patterns_discovered),
        'date_range': {
            'start': min(sessions.keys()),
            'end': max(sessions.keys())
        }
    }


def format_system_log_entry(stats):
    """Format new system log entry HTML"""
    today = datetime.now()
    date_str = today.strftime("%B %d, %Y")
    
    return f'''                    <div class="log-entry">
                        <div class="log-date">{date_str}</div>
                        <div class="log-title">Session Data Update</div>
                        <div class="log-description">
                            Processed {stats['session_count']} sessions from recent activity. 
                            Total pixels: {stats['total_pixels']:,} | 
                            Steps: {stats['total_steps']:,} | 
                            Dominant emotion: {stats['dominant_emotion']} | 
                            Top skill: {stats['top_skill']} | 
                            New patterns: {stats['unique_patterns']}
                        </div>
                    </div>'''


def update_index_html(stats):
    """Update index.html with new system log entry"""
    print(f"\n🔧 Updating index.html...")
    
    # Ensure we're on main branch and up to date
    os.chdir(WEBSITE_REPO)
    subprocess.run(['git', 'checkout', 'main'], capture_output=True, check=False)
    subprocess.run(['git', 'pull'], check=True)
    
    index_path = WEBSITE_REPO / "index.html"
    
    if not index_path.exists():
        print(f"❌ Could not find {index_path}")
        return False
    
    # Read current HTML
    with open(index_path, 'r') as f:
        html = f.read()
    
    # Check if today's date is already in system log
    today_str = datetime.now().strftime("%B %d, %Y")
    if f'<div class="log-date">{today_str}</div>' in html:
        print(f"⚠️  Today's update already exists, skipping...")
        return False
    
    # Create new log entry
    new_entry = format_system_log_entry(stats)
    
    # Find the system log section and insert after the opening div
    # Look for: <div class="system-log">
    pattern = r'(<div class="system-log">)'
    replacement = r'\1\n' + new_entry
    
    html = re.sub(pattern, replacement, html, count=1)
    
    # Write updated HTML
    with open(index_path, 'w') as f:
        f.write(html)
    
    print(f"✓ Added system log entry to index.html")
    return True


def push_website_changes(stats):
    """Commit and push website changes"""
    print(f"\n📤 Pushing website changes...")
    
    os.chdir(WEBSITE_REPO)
    subprocess.run(['git', 'add', 'index.html'], check=True)
    
    # Check if there are actually changes to commit
    result = subprocess.run(['git', 'diff', '--cached', '--quiet'], capture_output=True)
    if result.returncode == 0:
        print("⚠️  No changes detected in index.html (already up to date)")
        return False
    
    commit_msg = f"Update session insights: {stats['session_count']} sessions, {stats['unique_patterns']} patterns"
    subprocess.run(['git', 'commit', '-m', commit_msg], check=True)
    subprocess.run(['git', 'push'], check=True)
    print(f"✓ Website updated!")
    return True


def main():
    # Check for debug flag
    debug = '--debug' in sys.argv
    
    print("="*60)
    print("🧠 AURORA SESSION INSIGHTS UPDATER")
    print("="*60)
    
    # Ensure website repo exists
    ensure_repo_exists(WEBSITE_REPO, WEBSITE_REPO_URL)
    
    # Load all insights
    print(f"\n📂 Loading insights from: {INSIGHTS_FILE}")
    all_insights = load_session_insights()
    print(f"✓ Loaded {len(all_insights)} total sessions")
    
    # Get last update date
    last_update = get_last_update_date()
    
    # Filter new sessions
    new_sessions = filter_new_sessions(all_insights, last_update)
    
    if not new_sessions:
        print("\n⚠️  No new sessions found since last update")
        print("="*60)
        sys.exit(0)
    
    print(f"✓ Found {len(new_sessions)} new sessions")
    
    # Debug mode - show sample session structure
    if debug:
        print("\n🔍 DEBUG: Sample session structure:")
        sample_session = list(new_sessions.values())[0]
        print(json.dumps(sample_session, indent=2))
        print("\n" + "="*60)
    
    # Calculate statistics
    print(f"\n📊 Calculating statistics...")
    stats = calculate_stats(new_sessions)
    
    print(f"\n📈 SUMMARY:")
    print(f"  Sessions: {stats['session_count']}")
    print(f"  Total Pixels: {stats['total_pixels']:,}")
    print(f"  Total Steps: {stats['total_steps']:,}")
    print(f"  Dominant Emotion: {stats['dominant_emotion']}")
    print(f"  Top Skill: {stats['top_skill']}")
    print(f"  Unique Patterns: {stats['unique_patterns']}")
    
    # Update website
    if update_index_html(stats):
        result = push_website_changes(stats)
        
        if result:
            # Save current date as last update
            today = datetime.now().strftime("%Y-%m-%d")
            save_last_update_date(today)
            
            print("\n" + "="*60)
            print("✨ SUCCESS! Session insights updated!")
            print("="*60)
            print(f"View at: https://elijahsylar.github.io/aurora_ai/#about")
            print(f"Note: GitHub Pages may take 1-2 minutes to rebuild")
            print("="*60)
        else:
            print("\n⚠️  No changes pushed (HTML wasn't modified)")
    else:
        print("\n⚠️  Update skipped (already exists or no changes)")


if __name__ == "__main__":
    main()
