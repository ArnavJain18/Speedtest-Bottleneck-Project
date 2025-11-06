import subprocess
import pandas as pd
import os
import argparse
from tqdm import tqdm
import json
from pprint import pprint
import numpy as np
import dpkt
import socket

def parse_speedtest_packets(pcap_file):
    """Extract packet details from a pcap file.

    Args:
        pcap_file (str): The path to the pcap file.

    Returns:
        pd.DataFrame: A DataFrame containing the extracted packet details.
    """
    pkts = []

    with open(pcap_file, 'rb') as f:
        pcap = dpkt.pcap.Reader(f)

        for timestamp, buf in pcap:
            eth = dpkt.ethernet.Ethernet(buf)
            if isinstance(eth.data, dpkt.ip.IP):
                ip = eth.data
                src_ip = socket.inet_ntoa(ip.src)
                dst_ip = socket.inet_ntoa(ip.dst)
                ip_len = ip.len

                src_port, dst_port = 0, 0
                if isinstance(ip.data, dpkt.tcp.TCP):
                    tcp = ip.data
                    src_port = tcp.sport
                    dst_port = tcp.dport
                pkts.append({
                    'timestamp': timestamp,
                    'src_ip': src_ip,
                    'dst_ip': dst_ip,
                    'ip_pkt_length': ip_len,
                    'src_port': src_port,
                    'dst_port': dst_port
                })

    df = pd.DataFrame(pkts)
    return df


def get_upload_start_time(sent_pkts, recv_pkts):
    """
    Get the upload start time based on the sent and received packets.

    Args:
        sent_pkts (pd.DataFrame): DataFrame containing the sent packets.
        recv_pkts (pd.DataFrame): DataFrame containing the received packets.

    Returns:
        int: The upload start time.
    """
    # Divide into tiny time slots
    delta = 1e5  # Time slot duration (100 ms, can be tweaked)
    t_min = sent_pkts['timestamp'].min()
    t_max = sent_pkts['timestamp'].max()
    if not sent_pkts.empty and not recv_pkts.empty:
        all_slots = list(np.arange(int(t_min), int(t_max), int(delta)))

        lo = 0
        hi = len(all_slots) - 1
        first_valid_slot = -1

        # Conduct a binary search to find the first upload start time where sent_len > recv_len
        while lo <= hi:
            up_start = (lo + hi) // 2
            slot = all_slots[up_start]

            sent_slot = sent_pkts[(sent_pkts['timestamp'] >= slot) & (sent_pkts['timestamp'] < slot + delta)]
            recv_slot = recv_pkts[(recv_pkts['timestamp'] >= slot) & (recv_pkts['timestamp'] < slot + delta)]

            sent_len = sent_slot['ip_pkt_length'].sum()
            recv_len = recv_slot['ip_pkt_length'].sum()

            if sent_len - recv_len >= 200:
                first_valid_slot = up_start  # This could be the first valid slot
                hi = up_start - 1            # Continue to search in the left half for earlier occurrences
            else:
                lo = up_start + 1

        # Return the first valid slot found, or -1 if no such slot was found
        if first_valid_slot != -1:
            return int(all_slots[first_valid_slot])
        else:
            return None
    else:
        print('Np.nan error found')
        return None

def preprocess_speedtest(metadata_file, pcap_file, extra_idle_time=10):
    """
    Preprocesses a speedtest NDT pcap file by filtering out speed test packets based on the test server IP address and host IP address from the metadata file.

    Args:
        pcap_file (str): The path to the pcap file.

    Returns:
        tuple: Contains the start time of the speed test, the calculated upload start time, 
               the upload start time (converted to microseconds), and the end time of the speed test.
    """
    # Read metadata
    try:    
        with open(metadata_file, 'r') as f:
            meta = json.load(f)
    except FileNotFoundError:
        raise FileNotFoundError(f"Metadata file not found: {metadata_file}")
    except json.JSONDecodeError:
        raise ValueError(f"Error decoding JSON from metadata file: {metadata_file}")

    # Identify the speed test variant

    if "ndt7" in meta['Measurements']:
        tool = 'ndt7'
    else:
        tool = 'ookla'

    try:
        host_ip = meta['Meta']['Interface_ip'][0]
    except IndexError:
        host_ip = ""

    speedtest_start = int(meta['Meta']['Speedtest_start_time'] * 1e6)
    speedtest_end = int(meta['Meta']['Speedtest_end_time'] * 1e6)

    if speedtest_end == 0: # happens when the speed test is not completed
        speedtest_end = int((meta['Meta']['Ping_end_time'] - extra_idle_time) * 1e6)

    # Read and process pcap file
    pkts = parse_speedtest_packets(pcap_file)

    top_two = pkts.groupby('src_ip')['ip_pkt_length'].sum().nlargest(2).index.tolist()

    server_ip = [ip for ip in top_two if ip != host_ip][0]

    pkts['timestamp'] = pkts['timestamp'] * 1e6 # Convert to microseconds

    # Sent packets (from host to server)
    sent_pkts = pkts[(pkts['src_ip'] == host_ip) & (pkts['dst_ip'] == server_ip)]

    # Received packets (from server to host)
    recv_pkts = pkts[(pkts['src_ip'] == server_ip) & (pkts['dst_ip'] == host_ip)]

    # Get upload start time
    up_start = get_upload_start_time(sent_pkts, recv_pkts)

    if up_start is None:
        # default to average of download start and upload end
        up_start = (speedtest_start + speedtest_end) // 2

    return speedtest_start, up_start, up_start, speedtest_end, server_ip

def extract_speedtest_boundaries(data_dir, extra_idle_time=10):
    """
    Extracts speed test boundaries from NDT and Ookla speed test packets. Writes to a JSON file.

    Args:
        data_dir (str): The directory containing the speed test pcap files.
    """
    # Get all pcap files
    pcap_files = [f for f in os.listdir(data_dir) if f.endswith('.pcap')]
    for pcap_file in tqdm(pcap_files):
        pcap_file = os.path.join(data_dir, pcap_file)
        try:
            down_start, down_end, up_start, up_end, server_ip = preprocess_speedtest(pcap_file, extra_idle_time)
        except Exception as e:
            print(f"Error processing {pcap_file}: {e}")
            continue
        # Write to JSON
        boundary_json = {
            'pcap_file': pcap_file,
            'download_start': down_start,
            'download_end': down_end,
            'upload_start': up_start,
            'upload_end': up_end,
            'server_ip': server_ip
        }
        boundary_file = pcap_file.replace('.pcap', '-boundaries.json')
        with open(boundary_file, 'w') as f:
            json.dump(boundary_json, f, indent=4)