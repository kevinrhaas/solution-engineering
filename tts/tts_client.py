from openai import OpenAI
from config import OPENAI_API_KEY, MODEL_NAME, VOICE, INSTRUCTIONS

client = OpenAI(api_key=OPENAI_API_KEY)

def generate_speech(text: str, output_path):
    response = client.audio.speech.create(
        model=MODEL_NAME,
        voice=VOICE,
        input=text,
        instructions=INSTRUCTIONS, 
    )
    output_path.write_bytes(response.content)
