import os
import json
import numpy as np
import tensorflow as tf
from tensorflow import keras
from sklearn.metrics import accuracy_score, classification_report
from ai.bilstm_model import load_training_data

def evaluate():
    print("Loading data...")
    X, y, label_encoder = load_training_data("data/training_data")
    
    if len(X) == 0:
        print("No data.")
        return
        
    model_path = os.path.join("ai", "isl_model.keras")
    print("Loading model...")
    model = keras.models.load_model(model_path)
    
    from sklearn.model_selection import train_test_split
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)
    
    print("Evaluating on Unseen Real-World Data (20% Validation Split)...")
    loss, accuracy = model.evaluate(X_val, y_val, verbose=0)
    
    y_pred_probs = model.predict(X_val, verbose=0)
    y_pred = np.argmax(y_pred_probs, axis=1)
    
    unique_labels = np.unique(y_val)
    target_names = label_encoder.inverse_transform(unique_labels)
    report = classification_report(y_val, y_pred, labels=unique_labels, target_names=target_names)
    
    print(f"\n=========================================")
    print(f"Overall Identification Accuracy: {accuracy * 100:.2f}%")
    print(f"=========================================\n")
    print(report)

if __name__ == "__main__":
    evaluate()
