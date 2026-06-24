import numpy as np
import os

def convert_to_bytes():
    recordings_dir = "data/training_data"
    output_dir = "../sign_translator/assets/recordings"
    
    os.makedirs(output_dir, exist_ok=True)
    
    files = [f for f in os.listdir(recordings_dir) if f.endswith(".npy")]
    if not files:
        print("No .npy files found.")
        return

    print(f"Converting {len(files)} files to Flutter binary format...")
    
    for fname in files:
        data = np.load(os.path.join(recordings_dir, fname))
        
        # Find the sequence with the MOST hand movement.
        # Hand features are indices 90 to 215 (Pose is 0-29, Face is 30-89)
        best_seq = None
        max_movement = -1
        
        for seq in data:
            hand_data = seq[:, 90:216]
            
            # Calculate standard deviation (movement) across the 30 frames for the hands
            movement = np.sum(np.std(hand_data, axis=0))
            
            if movement > max_movement:
                max_movement = movement
                best_seq = seq

        # Fallback just in case
        if best_seq is None:
            best_seq = data[len(data) // 2]
        
        # We only need the 2D relative coordinates (Pose, Face, LHand, RHand)
        drawing_sequence = best_seq[:, :216]
        
        flat = drawing_sequence.astype(np.float32).flatten()
        
        out_path = os.path.join(output_dir, fname.replace('.npy', '.bytes'))
        with open(out_path, 'wb') as f:
            f.write(flat.tobytes())
            
        print(f"Converted {fname} -> {out_path} ({len(flat)} floats)")

if __name__ == "__main__":
    convert_to_bytes()
