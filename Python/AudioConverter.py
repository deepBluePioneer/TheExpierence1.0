from pydub import AudioSegment
import os

# Directory containing the WAV files
directory = 'Python/AudioFiles'

# Loop through all files in the directory
for filename in os.listdir(directory):
    if filename.endswith(".wav"):
        # Full path of the WAV file
        wav_path = os.path.join(directory, filename)
        
        # Load the WAV file
        audio = AudioSegment.from_wav(wav_path)
        
        # Define the output path for the OGG file
        ogg_path = os.path.join(directory, filename.replace(".wav", ".ogg"))
        
        # Export the audio to OGG format
        audio.export(ogg_path, format="ogg")
        print(f"Converted {filename} to OGG format.")

print("All conversions complete.")
