import socket
import json
import csv
import argparse
import signal
import sys
import time

def signal_handler(sig, frame):
    print("\nStopping metrics collector...")
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)

def flatten_ue_info(ue_info, timestamp):
    """Flattens the nested dictionary of UE metrics."""
    flat = {'timestamp': timestamp}
    # UE container has the metrics
    if 'ue_container' in ue_info:
        flat.update(ue_info['ue_container'])
    return flat

def main():
    parser = argparse.ArgumentParser(description='Collect srsRAN DU metrics to CSV')
    parser.add_argument('--port', type=int, default=55555, help='UDP port to listen on')
    parser.add_argument('--output', type=str, required=True, help='Output CSV file path')
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', args.port))
    print(f"Listening for metrics on UDP port {args.port}...")

    csv_file = open(args.output, 'w', newline='')
    csv_writer = None
    
    # Buffer for partial JSON data
    buffer = ""

    try:
        while True:
            data, addr = sock.recvfrom(65535)
            text = data.decode('utf-8')
            
            if not text:
                continue

            buffer += text
            
            # srsRAN metrics are JSON objects often concatenated
            # e.g. {"timestamp":...}{"timestamp":...}
            # We split by '}{' to handle this
            
            while '}{' in buffer:
                # Find the split point
                split_idx = buffer.find('}{') + 1 # Include the first '}'
                
                # Extract the first complete JSON object string
                json_str = buffer[:split_idx]
                
                # Remove it from buffer
                buffer = buffer[split_idx:]
                
                process_json(json_str, csv_writer, csv_file)

            # Attempt to parse what remains if it looks complete (ends with })
            if buffer.strip().endswith('}'):
                 try:
                     process_json(buffer, csv_writer, csv_file)
                     buffer = ""
                 except json.JSONDecodeError:
                     # It might be incomplete, wait for more data
                     pass

    except KeyboardInterrupt:
        pass
    finally:
        csv_file.close()

def process_json(json_str, writer, file_handle):
    try:
        data = json.loads(json_str)
        # Uncomment to debug raw JSON
        # print(f"DEBUG: {data.keys()}")
        
        # We are looking for 'ue_list' which contains the per-UE metrics
        if 'ue_list' in data and data['ue_list']:
            timestamp = data.get('timestamp', time.time())
            
            for ue in data['ue_list']:
                flat_data = flatten_ue_info(ue, timestamp)
                write_row(flat_data, file_handle)
        
        # Also support top-level metrics if 'ue_list' is not present but other fields are
        # srsRAN 23.10+ format might be different
        elif 'metrics' in data: 
             # Handle alternate format if necessary
             pass

    except json.JSONDecodeError:
        print(f"JSON Decode Error: {json_str[:50]}...")
        pass
    except Exception as e:
        print(f"Error processing metrics: {e}")

# Global writer to keep state
global_csv_writer = None

def write_row(flat_data, file_handle):
    global global_csv_writer
    if global_csv_writer is None:
        global_csv_writer = csv.DictWriter(file_handle, fieldnames=flat_data.keys(), extrasaction='ignore')
        global_csv_writer.writeheader()
    
    # Handle case where new fields appear? srsRAN metrics are usually consistent.
    # If a field is missing, DictWriter fills empty. If extra, it raises error unless extrasaction='ignore'
    
    # For safety, let's re-create writer if keys don't match? No, that messes up the header.
    # We'll use extrasaction='ignore' to be safe, or just update headers?
    # Simpler: just write.
    try:
        global_csv_writer.writerow(flat_data)
        file_handle.flush()
    except ValueError:
        # If we have new keys, we might lose them or crash. 
        # For this test bench, the first packet usually defines the schema.
        pass

if __name__ == '__main__':
    main()

