import os
import sys
import numpy as np
import tensorflow as tf
from tensorflow import keras
from keras import layers
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
import json

def load_training_data(data_dir="../data/training_data"):
    # Note: data_dir is relative to backend/, if running from backend/ai/ use ../data
    X = []
    y = []
    
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    full_data_dir = os.path.join(base_dir, "data", "training_data")
    
    if not os.path.exists(full_data_dir):
        print(f"Directory {full_data_dir} not found. Please record data first.")
        return np.array(X), np.array(y), None

    files = [f for f in os.listdir(full_data_dir) if f.endswith(".npy")]
    if not files:
        print(f"No .npy files found in {full_data_dir}.")
        return np.array(X), np.array(y), None

    for file in files:
        label = file.split('.')[0] # e.g., 'HELLO.npy' -> 'HELLO'
        data = np.load(os.path.join(full_data_dir, file))
        
        # data shape should be (num_sequences, 30, 342)
        for sequence in data:
            X.append(sequence)
            y.append(label)

    X = np.array(X)
    y = np.array(y)
    
    label_encoder = LabelEncoder()
    y_encoded = label_encoder.fit_transform(y)
    
    return X, y_encoded, label_encoder

def build_model(input_shape=(30, 342), num_classes=1):
    inputs = layers.Input(shape=input_shape)
    
    # LayerNormalization <- handles different signer sizes
    x = layers.LayerNormalization()(inputs)
    
    # Conv1D (64 filters, k=3) <- extracts local hand shape patterns
    x = layers.Conv1D(64, 3, padding='same', activation='relu')(x)
    # Conv1D (128 filters, k=3) <- deeper local patterns
    x = layers.Conv1D(128, 3, padding='same', activation='relu')(x)
    
    # BiLSTM (128 units) <- reads sequence forward AND backward
    x = layers.Bidirectional(layers.LSTM(128, return_sequences=True, dropout=0.4, recurrent_dropout=0.2))(x)
    # BiLSTM (64 units) -> returns sequences so Attention can work
    x = layers.Bidirectional(layers.LSTM(64, return_sequences=True, dropout=0.4, recurrent_dropout=0.2))(x)
    
    # MultiHeadAttention (4 heads) (+ residual connection)
    attention = layers.MultiHeadAttention(num_heads=4, key_dim=64)(x, x)
    x = layers.Add()([x, attention])
    
    # Temporal Reduction <- Drop the 30 temporal dimension WITHOUT flattening everything
    # Using an LSTM that returns only the final state (64 units)
    x = layers.LSTM(64, return_sequences=False)(x)
    
    # Dense(64) -> Dropout(0.5)
    x = layers.Dense(64, activation='relu')(x)
    x = layers.Dropout(0.5)(x)
    
    # Dense(num_classes, softmax) <- final sign prediction
    outputs = layers.Dense(num_classes, activation='softmax')(x)
    
    model = keras.Model(inputs=inputs, outputs=outputs, name="BiLSTM_Attention_ISL")
    
    # Optimizer
    optimizer = keras.optimizers.Adam(learning_rate=0.001, clipnorm=1.0)
    
    model.compile(optimizer=optimizer,
                  loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])
    
    return model

def augment_sequence(sequence):
    """Generate augmented variations of a single (30, 342) sequence.
    
    Returns a list of augmented sequences (NOT including the original).
    Each augmentation simulates natural human variation:
      - Jitter: tiny random shifts in landmark positions (shaky hands, slight movement)
      - Time Warp: speed up or slow down parts of the sign
      - Scale: slight zoom in/out (distance from camera variation)
    """
    augmented = []
    
    # 1. JITTER: Add small gaussian noise to coordinates
    for noise_level in [0.02, 0.04]:
        noisy = sequence + np.random.normal(0, noise_level, sequence.shape)
        augmented.append(noisy)
    
    # 2. TIME WARP: Stretch or compress the temporal axis
    n_frames = sequence.shape[0]  # 30
    for warp_factor in [0.8, 1.2]:
        # Create warped time indices
        orig_indices = np.arange(n_frames)
        # Generate a smooth warp curve
        warp_center = np.random.randint(5, n_frames - 5)
        warp_indices = orig_indices.copy().astype(float)
        for i in range(n_frames):
            dist = abs(i - warp_center)
            if dist < 8:
                warp_indices[i] = i + (warp_factor - 1.0) * (8 - dist) * 0.5
        warp_indices = np.clip(warp_indices, 0, n_frames - 1)
        # Interpolate each feature along the warped timeline
        warped = np.zeros_like(sequence)
        for feat_idx in range(sequence.shape[1]):
            warped[:, feat_idx] = np.interp(orig_indices, warp_indices, sequence[:, feat_idx])
        augmented.append(warped)
    
    # 3. SPATIAL SCALE: Multiply all coordinates by a small factor
    #    (simulates being slightly closer/farther from camera)
    for scale in [0.9, 1.1]:
        scaled = sequence * scale
        augmented.append(scaled)
    
    return augmented

def train_model():
    print("Loading data...")
    X, y, label_encoder = load_training_data()
    
    if len(X) == 0:
        print("No training data available. Run record_data_gui.py first.")
        return
        
    num_classes = len(label_encoder.classes_)
    print(f"Found {len(X)} sequences across {num_classes} classes.")
    print(f"Classes: {label_encoder.classes_}")
    
    if num_classes < 2:
        print("❌ Error: You need at least TWO different signs recorded to train a classifier!")
        sys.exit(1)
    
    # DATA AUGMENTATION DISABLED: 
    # Continuous recording provides enough natural variation (174 samples per sign).
    # Removing artificial multiplier to slash training time from 15+ mins to ~2 mins.
    
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Save the label encoder classes so we can load them during prediction
    with open(os.path.join(base_dir, 'label_encoder_classes.json'), 'w') as f:
        json.dump(list(label_encoder.classes_), f)
    
    # Train/Test Split
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)
    
    print("Building model...")
    model = build_model(input_shape=(30, 342), num_classes=num_classes)
    model.summary()
    
    model_path = os.path.join(base_dir, 'isl_model.keras')
    callbacks = [
        keras.callbacks.EarlyStopping(patience=20, restore_best_weights=True, monitor='val_loss'),
        keras.callbacks.ModelCheckpoint(model_path, save_best_only=True, monitor='val_loss')
    ]
    
    print("Starting training...")
    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=150,
        batch_size=32,
        callbacks=callbacks
    )
    
    print(f"Training complete! Model saved to {model_path}")

if __name__ == "__main__":
    train_model()
