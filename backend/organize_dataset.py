"""
Dataset Organizer for ISL Training Data
========================================
Sorts video and .npy dataset files into categorized folders based on filename.

Rules:
  - Single-word files  → folder named after the word (UPPERCASE canonical name)
    e.g. Hello.mp4, hello.mp4, HELLO.mp4  → all go into HELLO/
    Original filenames are PRESERVED so the model trains on case variations.

  - Sentence files (filename has spaces / multiple words) → _sentences/ folder
    e.g. "where are you going.mp4" → _sentences/

Usage:
    python organize_dataset.py <source_folder>                   # copy mode (safe)
    python organize_dataset.py <source_folder> --move            # move mode
    python organize_dataset.py <source_folder> --dry-run         # preview only
    python organize_dataset.py <source_folder> -o <output_dir>   # custom output

Examples:
    python organize_dataset.py "C:/Users/me/Downloads/new_signs"
    python organize_dataset.py ./my_dataset --move --dry-run
"""

import os
import sys
import shutil
import argparse
from collections import defaultdict

# ---------------------------------------------------------------------------
# Supported file extensions
# ---------------------------------------------------------------------------
SUPPORTED_EXTENSIONS = {".mp4", ".avi", ".mov", ".npy", ".webm", ".mkv"}

# Folder name for sentence-type files
SENTENCES_FOLDER = "_sentences"


# ---------------------------------------------------------------------------
# Classification helpers
# ---------------------------------------------------------------------------
def get_name_without_extension(filename: str) -> str:
    """Return the filename without its extension.

    >>> get_name_without_extension("Hello.mp4")
    'Hello'
    >>> get_name_without_extension("where are you going.mp4")
    'where are you going'
    """
    return os.path.splitext(filename)[0]


def is_sentence(name: str) -> bool:
    """A file is a 'sentence' if its stem (name without extension) contains
    at least one space, indicating multiple words.

    >>> is_sentence("Hello")
    False
    >>> is_sentence("where are you going")
    True
    """
    return " " in name.strip()


def get_canonical_folder(name: str) -> str:
    """Return the canonical (UPPERCASE) folder name for a single-word file.

    >>> get_canonical_folder("hello")
    'HELLO'
    >>> get_canonical_folder("Go")
    'GO'
    """
    return name.strip().upper()


def make_unique_path(dest_path: str) -> str:
    """If dest_path already exists, append _1, _2, … until unique.

    >>> # If HELLO/hello.mp4 already exists:
    >>> make_unique_path("organized/HELLO/hello.mp4")
    'organized/HELLO/hello_1.mp4'
    """
    if not os.path.exists(dest_path):
        return dest_path

    base, ext = os.path.splitext(dest_path)
    counter = 1
    while os.path.exists(f"{base}_{counter}{ext}"):
        counter += 1
    return f"{base}_{counter}{ext}"


# ---------------------------------------------------------------------------
# Core organizer
# ---------------------------------------------------------------------------
def scan_source(source_dir: str) -> list:
    """Walk through source_dir and collect all supported files.

    Returns a list of (absolute_filepath, subfolder_label_or_None).
    - If the file is directly in source_dir root -> label is None (classify by filename)
    - If the file is inside a direct subdirectory of source_dir -> label is that
      subdirectory's name (used as the category regardless of filename)
    - Deeper nesting uses the first-level subdirectory name as the label.
    """
    collected = []
    for root, _dirs, files in os.walk(source_dir):
        # Determine the first-level subfolder name relative to source_dir
        rel = os.path.relpath(root, source_dir)
        if rel == ".":
            # Files directly in source_dir root — classify by filename
            subfolder_label = None
        else:
            # Use only the top-level subfolder name as the label
            # e.g. source/HELLO/session1/take.mp4 -> label = 'HELLO'
            subfolder_label = rel.split(os.sep)[0]

        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext in SUPPORTED_EXTENSIONS:
                collected.append((os.path.join(root, f), subfolder_label))
    return collected


def organize(source_dir: str, output_dir: str, move: bool = False,
             dry_run: bool = False) -> dict:
    """Organize files from source_dir into output_dir.

    Returns a summary dict with stats.
    """
    source_dir = os.path.abspath(source_dir)
    output_dir = os.path.abspath(output_dir)

    if not os.path.isdir(source_dir):
        print(f"[ERROR] Source folder does not exist: {source_dir}")
        sys.exit(1)

    file_entries = scan_source(source_dir)
    if not file_entries:
        print(f"[WARNING] No supported files found in: {source_dir}")
        print(f"  Supported extensions: {', '.join(sorted(SUPPORTED_EXTENSIONS))}")
        return {"total": 0, "words": 0, "sentences": 0, "folders": set()}

    # ---- Classify every file ----
    plan = []  # list of (src_path, dest_folder, dest_filename)
    for filepath, subfolder_label in file_entries:
        filename = os.path.basename(filepath)

        if subfolder_label is not None:
            # File lives inside a named subfolder — use that folder name as label.
            # Normalize to UPPERCASE; treat multi-word folder names as sentences.
            if is_sentence(subfolder_label):
                dest_folder = SENTENCES_FOLDER
            else:
                dest_folder = get_canonical_folder(subfolder_label)
        else:
            # File is in the root of source_dir — classify by filename.
            stem = get_name_without_extension(filename)
            if is_sentence(stem):
                dest_folder = SENTENCES_FOLDER
            else:
                dest_folder = get_canonical_folder(stem)

        plan.append((filepath, dest_folder, filename))

    # ---- Build summary for display ----
    folder_counts = defaultdict(list)
    for src, folder, fname in plan:
        folder_counts[folder].append(fname)

    # ---- Print plan ----
    action = "MOVE" if move else "COPY"
    mode_label = " [DRY RUN]" if dry_run else ""
    print()
    print("=" * 65)
    print(f"  Dataset Organizer - {action} Mode{mode_label}")
    print("=" * 65)
    print(f"  Source : {source_dir}")
    print(f"  Output : {output_dir}")
    print(f"  Files  : {len(file_entries)} found")
    print("-" * 65)

    # Sort folders: word folders alphabetically, _sentences last
    sorted_folders = sorted(folder_counts.keys(),
                            key=lambda f: (f == SENTENCES_FOLDER, f))

    word_count = 0
    sentence_count = 0

    for folder in sorted_folders:
        file_list = folder_counts[folder]
        if folder == SENTENCES_FOLDER:
            sentence_count = len(file_list)
            label = f"  [SENTENCE] {folder}/"
        else:
            word_count += len(file_list)
            label = f"  [WORD] {folder}/"

        print(label)
        for fname in sorted(file_list):
            print(f"      |-- {fname}")
        print()

    print("-" * 65)
    print(f"  Summary: {word_count} word files -> {len(sorted_folders) - (1 if sentence_count else 0)} folders")
    if sentence_count:
        print(f"           {sentence_count} sentence files -> {SENTENCES_FOLDER}/")
    print(f"  Total  : {len(file_entries)} files")
    print("=" * 65)

    # ---- Execute ----
    if dry_run:
        print("\n  [OK] Dry run complete - no files were changed.\n")
        return {
            "total": len(file_entries),
            "words": word_count,
            "sentences": sentence_count,
            "folders": set(f for f in sorted_folders if f != SENTENCES_FOLDER),
        }

    transferred = 0
    for src, folder, fname in plan:
        dest_dir = os.path.join(output_dir, folder)
        os.makedirs(dest_dir, exist_ok=True)

        dest_path = os.path.join(dest_dir, fname)
        dest_path = make_unique_path(dest_path)

        if move:
            shutil.move(src, dest_path)
        else:
            shutil.copy2(src, dest_path)

        transferred += 1

    action_past = "moved" if move else "copied"
    print(f"\n  [OK] Done! {transferred} files {action_past} to {output_dir}\n")

    return {
        "total": len(file_entries),
        "words": word_count,
        "sentences": sentence_count,
        "folders": set(f for f in sorted_folders if f != SENTENCES_FOLDER),
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Organize ISL dataset files into categorized folders.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python organize_dataset.py "C:/Users/me/Downloads/new_signs"
  python organize_dataset.py ./my_dataset --move
  python organize_dataset.py ./my_dataset --dry-run
  python organize_dataset.py ./my_dataset -o ./sorted_data
        """,
    )
    parser.add_argument(
        "source",
        help="Path to the folder containing dataset files to organize.",
    )
    parser.add_argument(
        "-o", "--output",
        default=None,
        help="Output directory (default: organized_dataset/ next to source).",
    )
    parser.add_argument(
        "--move",
        action="store_true",
        help="Move files instead of copying (destructive).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview the organization without touching any files.",
    )

    args = parser.parse_args()

    # Default output: organized_dataset/ inside the backend folder
    if args.output:
        output_dir = args.output
    else:
        output_dir = os.path.join(
            os.path.dirname(os.path.abspath(args.source)),
            "organized_dataset",
        )

    organize(args.source, output_dir, move=args.move, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
