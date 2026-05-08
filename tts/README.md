# TTS (Text to Speech) Project

A command-line tool to convert text files to speech using OpenAI's Text-to-Speech API.

## Features

- 🎤 Convert any text file to high-quality speech
- 📂 Flexible input/output directory management
- 🔧 Configurable voice settings via environment variables
- 📝 Line-by-line processing with numbered output files
- ⚡ Simple command-line interface
- 🛡️ Secure API key management

## Prerequisites

- Python 3.7+
- OpenAI API key
- `pip` for package installation

## Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd tts
   ```

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure environment:**
   ```bash
   cp .env.example .env
   ```
   
4. **Add your OpenAI API key to `.env`:**
   ```env
   OPENAI_API_KEY=your_actual_api_key_here
   ```

## Usage

### Basic Usage
```bash
python main.py input-file.txt output-directory
```

### Examples
```bash
# Convert a presentation script
python main.py presentation.txt audio-output

# Process chapter content
python main.py chapter1.txt audiobooks/chapter1

# Convert meeting notes
python main.py meeting-notes.txt recordings/meeting-2024-08-15
```

### Command Line Options
```bash
python main.py --help
```

## Input Format

Create a text file with one line per audio segment you want to generate:

**Example `script.txt`:**
```
Welcome to our presentation on data governance
Today we'll explore three key concepts
First, let's discuss data cataloging
Data lineage helps us understand data flow
Finally, we'll cover compliance and security
Thank you for your attention
```

This will generate 6 numbered MP3 files: `001-speech.mp3` through `006-speech.mp3`.

## Configuration

Customize the TTS settings in your `.env` file:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | *required* | Your OpenAI API key |
| `MODEL_NAME` | `gpt-4o-mini-tts` | OpenAI TTS model |
| `VOICE` | `sage` | Voice to use (alloy, echo, fable, onyx, nova, shimmer, sage, coral) |
| `INSTRUCTIONS` | *professional style* | Voice style instructions |

### Available Voices
- **alloy** - Neutral, balanced
- **echo** - Male, clear
- **fable** - British accent, articulate  
- **nova** - Young female, bright
- **onyx** - Deep male voice
- **shimmer** - Soft female voice
- **sage** - Professional, clear (recommended for technical content)
- **coral** - Warm, friendly

## Project Structure

```
tts/
├── main.py              # Main application
├── config.py            # Configuration management
├── tts_client.py        # OpenAI API client
├── requirements.txt     # Python dependencies
├── .env.example         # Environment template
├── .env                 # Your configuration (not in git)
├── .gitignore          # Git ignore rules
└── README.md           # This file

# User directories (not tracked in git):
├── input/              # Your text files
└── output/             # Generated audio files
```

## Error Handling

The application handles common errors gracefully:

- **Missing input file**: Clear error message with file path
- **Invalid API key**: OpenAI API error reporting
- **Network issues**: Connection error handling
- **Empty input**: Warning for files with no content

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is open source. Please check the repository for license details.

## Support

For issues and questions:
1. Check the [Issues](../../issues) page
2. Create a new issue with detailed information
3. Include your Python version and error messages
