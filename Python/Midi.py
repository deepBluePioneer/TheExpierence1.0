import mido

def midi_to_lua(midi_file_path, lua_file_path):
    # Open the MIDI file
    midi = mido.MidiFile(midi_file_path)

    # Calculate ticks per second
    ticks_per_beat = midi.ticks_per_beat
    tempo = 500000  # Default tempo in microseconds per beat (120 BPM)

    # Open a Lua file to write to
    with open(lua_file_path, 'w') as lua_file:
        # Write the module definition
        lua_file.write("local timings = {\n")
        
        # Iterate through all messages in the MIDI file
        for track in midi.tracks:
            lua_file.write(f'  ["{track.name}"] = {{\n')
            current_time = 0
            for msg in track:
                if msg.type == 'set_tempo':
                    tempo = msg.tempo
                current_time += mido.tick2second(msg.time, ticks_per_beat, tempo)
                if msg.type in ['note_on', 'note_off']:
                    lua_file.write(f'    {int(current_time * 1000)},\n')  # Convert seconds to milliseconds and write to file
            lua_file.write('  },\n')
        
        # Close the module definition
        lua_file.write("}\n")
        lua_file.write("\nreturn timings\n")

# Example usage
midi_file_path = 'Python/Protostar.mid'
lua_file_path = 'Python/Protostar.lua'
midi_to_lua(midi_file_path, lua_file_path)
