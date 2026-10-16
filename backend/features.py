"""Shared 342-dim feature extraction - used by BOTH recording and live inference.

CRITICAL: changing this function invalidates every file in data/training_data/
and requires re-recording + retraining.
"""
import numpy as np

# Column slices of the 342-dim vector (for analysis tools).
BLOCKS = {
    "pose": slice(0, 30),
    "face": slice(30, 90),
    "l_hand": slice(90, 153),
    "r_hand": slice(153, 216),
    "l_hand_world": slice(216, 279),
    "r_hand_world": slice(279, 342),
}


def extract_342_features(data):
    """Extract comprehensive 342-dimensional feature vector.
    
    Layout: 
    - Pose (2D relative): 10*3=30
    - Face (2D relative): 20*3=60
    - L Hand (2D relative): 21*3=63
    - R Hand (2D relative): 21*3=63
    - L Hand (3D world): 21*3=63
    - R Hand (3D world): 21*3=63
    Total = 342 features.
    
    This provides explicit finger placement (world) AND spatial positioning (relative).
    """
    
    # --- Step 1: Find body anchor and scale ---
    pose_nodes = data.get("pose", [])
    
    anchor_x, anchor_y, anchor_z = 0.5, 0.5, 0.0
    scale = 1.0
    
    if len(pose_nodes) > 12:
        nose = pose_nodes[0]
        anchor_x = nose.get("x", 0.5)
        anchor_y = nose.get("y", 0.5)
        anchor_z = nose.get("z", 0.0)
        
        ls = pose_nodes[11]
        rs = pose_nodes[12]
        dx = ls.get("x", 0) - rs.get("x", 0)
        dy = ls.get("y", 0) - rs.get("y", 0)
        shoulder_dist = (dx**2 + dy**2) ** 0.5
        if shoulder_dist > 0.01:
            scale = shoulder_dist
        else:
            scale = 0.2
    
    def normalize_and_flatten(nodes, target_len):
        if not nodes:
            return np.zeros(target_len * 3)
        subset = nodes[:target_len]
        while len(subset) < target_len:
            subset.append({"x": 0, "y": 0, "z": 0})
        arr = []
        for n in subset:
            nx = n.get("x", 0)
            ny = n.get("y", 0)
            nz = n.get("z", 0)
            if nx == 0 and ny == 0 and nz == 0:
                arr.extend([0.0, 0.0, 0.0])
            else:
                arr.extend([
                    (nx - anchor_x) / scale,
                    (ny - anchor_y) / scale,
                    nz / scale
                ])
        return np.array(arr)

    def flatten_raw(nodes, target_len):
        if not nodes:
            return np.zeros(target_len * 3)
        subset = nodes[:target_len]
        while len(subset) < target_len:
            subset.append({"x": 0, "y": 0, "z": 0})
        arr = []
        for n in subset:
            arr.extend([n.get("x", 0), n.get("y", 0), n.get("z", 0)])
        return np.array(arr)

    pose_subset = pose_nodes[11:21] if len(pose_nodes) > 20 else []
    pose_arr = normalize_and_flatten(pose_subset, 10)
    face_arr = normalize_and_flatten(data.get("face", []), 20)
    l_hand_arr = normalize_and_flatten(data.get("left_hand", []), 21)
    r_hand_arr = normalize_and_flatten(data.get("right_hand", []), 21)
    
    # 3D World Landmarks (no anchor needed, they are hand-centric in meters)
    l_hand_world_arr = flatten_raw(data.get("left_hand_world", []), 21)
    r_hand_world_arr = flatten_raw(data.get("right_hand_world", []), 21)

    return np.concatenate([
        pose_arr, face_arr, 
        l_hand_arr, r_hand_arr, 
        l_hand_world_arr, r_hand_world_arr
    ])
