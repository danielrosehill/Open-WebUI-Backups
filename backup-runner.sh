#!/bin/bash

# --- Configuration ---
 
OBJ_B2_ID="R4nD0MCh4R4cT3rS" 
OBJ_B2_KEY="4LpHaNum3r1cK3y"  
OBJ_B2_BUCKET="pR1Va73Buck3t" 
export OBJ_B2_ID OBJ_B2_KEY

OBJ_BACKUP_DIR="/opt/backup/storage"
OBJ_BACKUP_LOG_DIR="/var/log/backup_logs"
OBJ_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OBJ_MAIN_SQLITE_DB="/var/lib/private/data/app.db"
OBJ_VECTOR_DB_DIR="/var/lib/private/data/feature_store"
OBJ_CONTAINER_NAME="hidden-app"

# --- Helper Functions ---
log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "$OBJ_BACKUP_LOG_DIR/operation_report_$OBJ_TIMESTAMP.log"
}

error_exit() {
  log "CRITICAL: $1" >&2
  echo "CRITICAL: $1" >> "$OBJ_BACKUP_LOG_DIR/operation_report_$OBJ_TIMESTAMP.log"
  exit 99
}

# --- Main Script ---
echo "Process started at $(date +'%Y-%m-%d %H:%M:%S')" >> "$OBJ_BACKUP_LOG_DIR/operation_report_$OBJ_TIMESTAMP.log"
log "Initiating safeguard procedures..."

log "Halting container..."
docker stop "$OBJ_CONTAINER_NAME" || error_exit "Failed to halt container."
echo "Container halted at $(date +'%Y-%m-%d %H:%M:%S')" >> "$OBJ_BACKUP_LOG_DIR/operation_report_$OBJ_TIMESTAMP.log"

sleep 3
sync

log "Preparing archive location..."
mkdir -p "$OBJ_BACKUP_DIR" || error_exit "Failed to prepare archive location."

log "Securing database..."
sqlite3 "$OBJ_MAIN_SQLITE_DB" ".backup '$OBJ_BACKUP_DIR/app_data_$OBJ_TIMESTAMP.dat'"  || error_exit "Failed to secure database."

log "Archiving feature store..."
tar -czvf "$OBJ_BACKUP_DIR/feature_store_$OBJ_TIMESTAMP.tar.gz" "$OBJ_VECTOR_DB_DIR" || error_exit "Failed to archive feature store."

log "Purging intermediary files..."
rm -f "$OBJ_BACKUP_DIR/app_data_$OBJ_TIMESTAMP.dat"
rm -f "$OBJ_BACKUP_DIR/feature_store_$OBJ_TIMESTAMP.tar.gz"

log "Bundling archives..."
tar -czvf "$OBJ_BACKUP_DIR/complete_archive_$OBJ_TIMESTAMP.tar.gz" -C "$OBJ_BACKUP_DIR" --exclude='.*' . || {
  log "Retrying bundle creation..."
  sleep 2

  tar -czvf "$OBJ_BACKUP_DIR/complete_archive_$OBJ_TIMESTAMP.tar.gz" -C "$OBJ_BACKUP_DIR" --exclude='.*' . || error_exit "Failed to create bundle after retry."
}

log "Verifying remote storage location..."
rclone mkdir "b2:$OBJ_B2_BUCKET" || {
  if ! rclone lsd "b2:$OBJ_B2_BUCKET" 2>&1 | grep -q "Directory not found"; then
    log "Remote storage location exists, proceeding..."
  else
    error_exit "Failed to verify remote storage location."
  fi
}

log "Resuming container..."
docker start "$OBJ_CONTAINER_NAME" || error_exit "Failed to resume container."
echo "Container resumed at $(date +'%Y-%m-%d %H:%M:%S')" >> "$OBJ_BACKUP_LOG_DIR/operation_report_$OBJ_TIMESTAMP.log"

log "Transmitting archive..."
rclone copy "$OBJ_BACKUP_DIR/complete_archive_$OBJ_TIMESTAMP.tar.gz" "b2:$OBJ_B2_BUCKET" || error_exit "Failed to transmit archive."

log "Sanitizing local storage..."
rm -f "$OBJ_BACKUP_DIR/complete_archive_$OBJ_TIMESTAMP.tar.gz"

log "Process completed!"
echo "Process finalized successfully at $(date +'%Y-%m-%d %H:%M:%S')" >> "$OBJ_BACKUP_LOG_DIR/operation_report_$OBJ_TIMESTAMP.log"

exit 0