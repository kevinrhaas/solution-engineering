from pathlib import Path
from dotenv import load_dotenv
import os

load_dotenv()

# Configuration for the TTS application with environment variables
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# OpenAI settings (with defaults)
MODEL_NAME = os.getenv("MODEL_NAME", "gpt-4o-mini-tts")
VOICE = os.getenv("VOICE", "sage")

# Instructions for the TTS model
INSTRUCTIONS = os.getenv("INSTRUCTIONS", '''
Voice: Relaxed, clear, and composed, professional, but very easygoing

Tone: Neutral and informative, approachable.
''').strip()
