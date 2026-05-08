import argparse
from tts_client import generate_speech
from pathlib import Path

INPUT_FILE = Path(__file__).parent / "input.txt"

def main():
    parser = argparse.ArgumentParser(description='Convert text to speech using OpenAI TTS')
    parser.add_argument('input_file', 
                       type=Path,
                       help='Input text file containing lines to convert to speech')
    parser.add_argument('output_dir', 
                       help='Output directory for generated MP3 files (will be created if it doesn\'t exist)')
    
    args = parser.parse_args()
    
    # Convert output_dir to Path and create if it doesn't exist
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Using output directory: {output_dir.absolute()}")
    
    # Check if input file exists
    input_file = Path(args.input_file)
    if not input_file.exists():
        print(f"Error: Input file '{input_file}' not found!")
        return 1
    
    # Read and process the input file
    with input_file.open("r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]  # skip empty lines
    
    if not lines:
        print(f"Warning: No content found in '{input_file}'")
        return 0
    
    print(f"Processing {len(lines)} lines from '{input_file}'...")
    
    for idx, line in enumerate(lines, start=1):
        filename = f"{idx:03d}-speech.mp3"
        output_path = output_dir / filename
        print(f"Generating speech for line {idx}: {line[:50]}{'...' if len(line) > 50 else ''}")
        generate_speech(line, output_path)
        print(f"  → Saved to {output_path}")
    
    print(f"\n✅ Complete! Generated {len(lines)} audio files in '{output_dir}'")
    return 0

if __name__ == "__main__":
    exit(main())
