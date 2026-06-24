import os
import numpy as np

d = "data/training_data"

# Check ONLY hand features for similarity
print("--- Hand-only similarity (features 90-215 = left_hand + right_hand) ---")
sign_means = {}
for f in sorted(os.listdir(d)):
    if f.endswith(".npy"):
        data = np.load(os.path.join(d, f))
        label = f.replace(".npy", "")
        # Only look at hand features (indices 90-215)
        hand_data = data[:, :, 90:216]
        sign_means[label] = np.mean(hand_data, axis=(0, 1))

labels = list(sign_means.keys())
for i in range(len(labels)):
    for j in range(i+1, len(labels)):
        a = sign_means[labels[i]]
        b = sign_means[labels[j]]
        norm_a = np.linalg.norm(a)
        norm_b = np.linalg.norm(b)
        if norm_a > 0 and norm_b > 0:
            cos_sim = np.dot(a, b) / (norm_a * norm_b)
        else:
            cos_sim = 0
        marker = " ⚠️" if cos_sim > 0.95 else ""
        print(f"  {labels[i]:12s} vs {labels[j]:12s}: {cos_sim:.4f}{marker}")

# Also check: how many frames per sign have RIGHT hand detected?
print("\n--- Right hand detection rate per sign ---")
for f in sorted(os.listdir(d)):
    if f.endswith(".npy"):
        data = np.load(os.path.join(d, f))
        label = f.replace(".npy", "")
        rh = data[:, :, 153:216]  # right hand features
        n_frames = data.shape[0] * data.shape[1]
        nonzero_frames = sum(1 for seq in data for frame in seq if np.any(frame[153:216] != 0))
        print(f"  {label}: {nonzero_frames}/{n_frames} frames ({nonzero_frames/n_frames*100:.0f}%)")
