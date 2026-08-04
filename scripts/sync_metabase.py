#!/usr/bin/env python3
"""
Metabase SQL Question Sync Tool
---------------------------------
Automatically syncs local SQL files in `models/BIFT/npl/metabase/` to Metabase Question Cards.

Authentication:
    Uses Metabase Session ID (X-Metabase-Session header & Cookie session).

Usage:
    # 1. Sync all SQL files using default METABASE_SESSION_ID
    python3 scripts/sync_metabase.py --all

    # 2. Sync a single SQL file
    python3 scripts/sync_metabase.py models/BIFT/npl/metabase/metabase_npl_channel_summary.sql

    # 3. Dry-run mode (Preview updates without applying)
    python3 scripts/sync_metabase.py --all --dry-run
"""

import os
import re
import sys
import json
import argparse
import requests

def load_env_file():
    """Load environment variables from root .env file if present."""
    env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")
    if not os.path.exists(env_path):
        env_path = ".env"
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.strip().strip("'\"")
                    if key and key not in os.environ:
                        os.environ[key] = val

load_env_file()

# Default Metabase Settings (loaded from .env or system environment)
DEFAULT_METABASE_URL = os.getenv("METABASE_URL", "http://localhost:9902")
DEFAULT_SESSION_ID = os.getenv("METABASE_SESSION_ID", "")


# File to Question ID mapping
FILE_QUESTION_MAPPING = {
    "metabase_npl_gsalesforce1_summary.sql": 87,
    "metabase_npl_gsalesforce1_omset_week.sql": 88,
    "metabase_npl_gsalesforce2_summary.sql": 89,
    "metabase_npl_gsalesforce2_omset_week.sql": 90,
    "metabase_npl_salesforce_summary.sql": 91,
    "metabase_npl_salesforce_omset_week.sql": 92,
    "metabase_npl_channel_summary.sql": 93,
    "metabase_npl_channel_omset_week.sql": 94,
    "metabase_npl_group_channel_summary.sql": 95,
    "metabase_npl_group_channel_omset_week.sql": 96,
    "metabase_npl_salesman_summary.sql": 97,
    "metabase_npl_salesman_omset_week.sql": 98,
    "metabase_npl_classification_summary.sql": 99,
    "metabase_npl_classification_omset_week.sql": 100,
    "metabase_npl_by_gsalesforce1.sql": 85,
}

METABASE_DIR = "models/BIFT/npl/metabase"


def build_auth_headers(session_id="", user="", password="", base_url=""):
    """Construct headers using Session ID or Username/Password login."""
    headers = {"Content-Type": "application/json"}

    # Method 1: Use Session ID token if provided
    if session_id:
        headers["X-Metabase-Session"] = session_id
        headers["Cookie"] = f"metabase.SESSION={session_id}"
        return headers

    # Method 2: Login via API if user/password provided
    if user and password:
        login_url = f"{base_url.rstrip('/')}/api/session"
        try:
            res = requests.post(login_url, json={"username": user, "password": password}, timeout=5)
            if res.status_code == 200:
                token = res.json().get("id")
                if token:
                    headers["X-Metabase-Session"] = token
                    headers["Cookie"] = f"metabase.SESSION={token}"
                    return headers
        except Exception as e:
            print(f"⚠️ Login API attempt failed: {e}")

    return headers



def get_card_question_id(file_path):
    """Extract Question ID from SQL header comment or mapping dict."""
    filename = os.path.basename(file_path)
    
    # First check SQL file header comment e.g. `-- Question ID: 87`
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read(500)
        match = re.search(r"--\s*(?:Question ID|Card ID):\s*(\d+)", content, re.IGNORECASE)
        if match:
            return int(match.group(1))
            
    # Fallback to mapping dictionary
    return FILE_QUESTION_MAPPING.get(filename)


def get_current_sql(card_data):
    """Extract current SQL string regardless of Metabase version (MBQL classic vs MBQL 50+)."""
    dataset_query = card_data.get("dataset_query", {})
    
    # Check Format A: Classic native dictionary e.g. {"query": "SELECT ..."}
    if "native" in dataset_query:
        native_obj = dataset_query["native"]
        if isinstance(native_obj, dict):
            return native_obj.get("query", "").strip()
        elif isinstance(native_obj, str):
            return native_obj.strip()

    # Check Format B: MBQL 50 stages array e.g. stages: [{"native": "SELECT ..."}]
    stages = dataset_query.get("stages", [])
    if stages and isinstance(stages, list) and len(stages) > 0:
        stage = stages[0]
        if isinstance(stage, dict):
            native_val = stage.get("native")
            if isinstance(native_val, dict):
                return native_val.get("query", "").strip()
            elif isinstance(native_val, str):
                return native_val.strip()

    return ""


def set_new_sql(card_data, new_sql):
    """Set new SQL string across both classic and MBQL 50+ schemas."""
    dataset_query = card_data.setdefault("dataset_query", {})

    # Check Format B: MBQL 50 stages array
    if "stages" in dataset_query and isinstance(dataset_query["stages"], list) and len(dataset_query["stages"]) > 0:
        stage = dataset_query["stages"][0]
        if isinstance(stage.get("native"), dict):
            stage["native"]["query"] = new_sql
        else:
            stage["native"] = new_sql
        return

    # Check Format A: Classic native query dictionary
    if "native" in dataset_query and isinstance(dataset_query["native"], dict):
        dataset_query["native"]["query"] = new_sql
    else:
        dataset_query["native"] = {"query": new_sql}


def sync_file(file_path, headers, base_url, dry_run=False):
    """Sync a single SQL file to Metabase Question Card."""
    card_id = get_card_question_id(file_path)
    if not card_id:
        print(f"⚠️  Skipping {os.path.basename(file_path)}: No mapped Metabase Question ID found.")
        return False

    with open(file_path, "r", encoding="utf-8") as f:
        new_sql = f.read().strip()

    card_url = f"{base_url.rstrip('/')}/api/card/{card_id}"

    # Step 1: GET existing card info
    res = requests.get(card_url, headers=headers, timeout=10)
    if res.status_code != 200:
        print(f"❌ Failed to fetch Card ID {card_id} for {os.path.basename(file_path)}: {res.status_code} {res.text}")
        return False

    card_data = res.json()
    current_sql = get_current_sql(card_data)

    if current_sql == new_sql:
        print(f"✅ Card ID {card_id} ({card_data.get('name')}) is already up to date.")
        return True

    if dry_run:
        print(f"🔍 [DRY-RUN] Would update Card ID {card_id} ({card_data.get('name')}) with {os.path.basename(file_path)}")
        return True

    # Step 2: Update SQL text in dataset_query
    set_new_sql(card_data, new_sql)

    # Step 3: PUT updated card back to Metabase
    put_res = requests.put(card_url, headers=headers, json=card_data, timeout=10)
    if put_res.status_code == 200:
        print(f"🚀 Successfully updated Card ID {card_id} ({card_data.get('name')}) from {os.path.basename(file_path)}")
        return True
    else:
        print(f"❌ Failed to update Card ID {card_id}: {put_res.status_code} {put_res.text}")
        return False



def main():
    parser = argparse.ArgumentParser(description="Sync Metabase SQL queries from local files to Metabase Questions.")
    parser.add_argument("file", nargs="?", help="Path to specific SQL file to sync")
    parser.add_argument("--all", action="store_true", help="Sync all SQL files in models/BIFT/npl/metabase/")
    parser.add_argument("--dry-run", action="store_true", help="Preview updates without making API calls")
    parser.add_argument("--url", default=DEFAULT_METABASE_URL, help="Metabase base URL")
    # parser.add_argument("--cookie", default=DEFAULT_COOKIE, help="Metabase Cookie header string")
    parser.add_argument("--session-id", default=DEFAULT_SESSION_ID, help="Metabase session ID token")
    parser.add_argument("--user", default=os.getenv("METABASE_USER", ""), help="Optional Metabase username")
    parser.add_argument("--password", default=os.getenv("METABASE_PASS", ""), help="Optional Metabase password")
    
    args = parser.parse_args()

    if not args.file and not args.all:
        parser.print_help()
        sys.exit(1)

    files_to_sync = []
    if args.file:
        files_to_sync.append(args.file)
    elif args.all:
        if os.path.exists(METABASE_DIR):
            files_to_sync = [
                os.path.join(METABASE_DIR, f)
                for f in sorted(os.listdir(METABASE_DIR))
                if f.endswith(".sql")
            ]
        else:
            print(f"❌ Directory {METABASE_DIR} does not exist!")
            sys.exit(1)

    headers = build_auth_headers(
        session_id=args.session_id,
        user=args.user,
        password=args.password,
        base_url=args.url
    )
    
    print(f"🔌 Connecting to Metabase at {args.url} using Cookie/Session Auth...\n")

    success_count = 0
    for file_path in files_to_sync:
        if sync_file(file_path, headers, args.url, dry_run=args.dry_run):
            success_count += 1

    print(f"\n🎉 Sync completed! ({success_count}/{len(files_to_sync)} questions checked/synced)")


if __name__ == "__main__":
    main()
