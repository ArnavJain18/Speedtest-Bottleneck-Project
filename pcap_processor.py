import json
import sys
import socket
import os
import dpkt
from scapy.all import rdpcap, IP, IPv6, TCP
import speedtest_boundaries


def save_rtt_samples(pcap_file, metadata_file: str, metadata_out: str = ""):
    """
    Detect probing method and calculate RTT for ICMP Echo Replies and TTL Exceeded packets or UDP packets.

    Args:
        pcap_file (str): Path to pcap file.
        metadata_file (str): Path to metadata file.
        metadata_out (str): Path to metadata out file. (optional, writes to `metadata_file` if empty)
    """
    # pcap = rdpcap(pcap_file, count=1)
    pcap = dpkt.pcap.Reader(open(pcap_file, "rb"))
    icmp_echo_count = 0
    udp_count = 0
    for timestamp, buf in pcap:
        eth = dpkt.ethernet.Ethernet(buf)

        # Skip non-IP packets
        if not isinstance(eth.data, dpkt.ip.IP):
            continue
        ip = eth.data

        # Count ICMP Echo packets
        if isinstance(ip.data, dpkt.icmp.ICMP):
            icmp = ip.data
            if isinstance(icmp.data, dpkt.icmp.ICMP.Echo):
                icmp_echo_count += 1

        # Count UDP packets
        elif isinstance(ip.data, dpkt.udp.UDP):
            udp_count += 1

    if udp_count > icmp_echo_count:
        # UDP probing detected
        save_rtt_samples_udp(pcap_file, metadata_file, metadata_out)
    else:   
        # ICMP probing detected
        save_rtt_samples_icmp(pcap_file, metadata_file, metadata_out)

def save_rtt_samples_icmp(pcap_file: str, metadata_file: str, metadata_out: str = "", extra_idle_time=10):
    """
    Calculate RTT for ICMP Echo Replies and TTL Exceeded packets.

    Args:
        pcap_file (str): Path to pcap file.
        metadata_file (str): Path to metadata file.
        metadata_out (str): Path to metadata out file. (optional, writes to `metadata_file` if empty)
    """
    pcap = dpkt.pcap.Reader(open(pcap_file, "rb"))

    samples = {}
    slots = 0
    # to_print = {}
    for timestamp, buf in pcap:
        eth = dpkt.ethernet.Ethernet(buf)

        # Skip non-IP packets
        if not isinstance(eth.data, dpkt.ip.IP):
            continue
        ip = eth.data

        # Skip non-ICMP packets
        if not isinstance(ip.data, dpkt.icmp.ICMP):
            continue

        icmp = ip.data
        
        # Handle ICMP Echo
        if isinstance(icmp.data, dpkt.icmp.ICMP.Echo):
            # ICMP packet Seq No
            seq_no = icmp.data.seq
            src_ip = dpkt.utils.inet_to_str(ip.src)
            des_ip = dpkt.utils.inet_to_str(ip.dst)
            # Handle ICMP Echo Request
            if icmp.type == dpkt.icmp.ICMP_ECHO:
                
                # Add a sample for each ICMP Echo Request
                samples[seq_no] = {
                    "ttl": ip.ttl,
                    "round": 0,
                    "reply_ip": "",
                    "send_time": timestamp,
                    "recv_time": 0.0,
                    "rtt": 0.0,
                    "icmp_seq_no": seq_no,
                    "src ip": src_ip,
                    "des_ip": des_ip
                }
                # if ip.ttl == 2:
                #     print('REQ', samples[seq_no])
                    # to_print[seq_no] = 1
                # Update slots based on max ttl
                if ip.ttl >= slots:
                    slots = ip.ttl + 1                                                                                                                                                                                                                                                            

            # Handle ICMP Echo Reply
            elif icmp.type == dpkt.icmp.ICMP_ECHOREPLY:
                # Update sample with reply_ip and recv_time
                if seq_no in samples:
                    samples[seq_no].update(
                        {
                            "reply_ip": dpkt.utils.inet_to_str(ip.src),
                            "recv_time": timestamp,
                        }
                    )
                    # if seq_no in to_print:
                    #     print('RESP', samples[seq_no], slots)

        # Handle ICMP TTL Exceeded
        elif isinstance(icmp.data, dpkt.icmp.ICMP.TimeExceed):
            time_exceed = icmp.data

            if not isinstance(time_exceed.data, dpkt.ip.IP):
                continue
            req_ip = time_exceed.data

            if not isinstance(req_ip.data, dpkt.icmp.ICMP):
                continue
            req_icmp = req_ip.data

            # ICMP request packet Seq No
            seq_no = req_icmp.data.seq

            # Update sample with reply_ip and recv_time
            if seq_no in samples:
                samples[seq_no]["reply_ip"] = dpkt.utils.inet_to_str(ip.src)
                samples[seq_no]["recv_time"] = timestamp
                # if seq_no in to_print:
                #     print('TTLEXCEED', samples[seq_no])
    # Calculate round and rtt
    for sample in samples.values():
        sample["round"] = (sample["icmp_seq_no"] // slots) + 1

        if sample["recv_time"] != 0:
            sample["rtt"] = round(1000 * (sample["recv_time"] - sample["send_time"]), 6)
            # if sample["ttl"] <=2:
                # print(sample)
    down_start, down_end, up_start, up_end, server_ip = speedtest_boundaries.preprocess_speedtest(metadata_file, pcap_file, extra_idle_time)
    boundaries = {
        'pcap_file': pcap_file,
        'download_start': down_start,
        'download_end': down_end,
        'upload_start': up_start,
        'upload_end': up_end,
        'server_ip': server_ip
    }

    # Read & update metadata
    with open(metadata_file, "r") as fh:
        data = json.load(fh)
        data["Measurements"]["rtt_samples"] = list(samples.values())
        data["Measurements"]["boundaries"] = boundaries

    # Write metadata
    with open(metadata_out or metadata_file, "w") as fh:
        json.dump(data, fh)

def save_rtt_samples_udp(pcap_file: str, metadata_file: str, metadata_out: str = "", extra_idle_time=10):
    """
    Calculate RTT for UDP and TTL Exceeded packets.

    Args:
        pcap_file (str): Path to pcap file.
        metadata_file (str): Path to metadata file.
        metadata_out (str): Path to metadata out file. (optional, writes to `metadata_file` if empty)
    """
    pcap = dpkt.pcap.Reader(open(pcap_file, "rb"))

    samples = {}
    slots = 0

    for timestamp, buf in pcap:
        eth = dpkt.ethernet.Ethernet(buf)

        # Skip non-IP packets
        if not isinstance(eth.data, dpkt.ip.IP):
            continue

        ip = eth.data
        src_ip = dpkt.utils.inet_to_str(ip.src)
        des_ip = dpkt.utils.inet_to_str(ip.dst)
        # Handle UDP probing packets
        if isinstance(ip.data, dpkt.udp.UDP):
            udp = ip.data
            # ICMP packet Seq No
            seq_no = udp.dport
            # Add a sample for each ICMP Echo Request
            samples[seq_no] = {
                "ttl": ip.ttl,
                "round": 0,
                "reply_ip": "",
                "send_time": timestamp,
                "recv_time": 0.0,
                "rtt": 0.0,
                "udp_dest_port": seq_no,
                "src ip": src_ip,
                "des_ip": des_ip
            }
            # Update slots based on max ttl
            if ip.ttl >= slots:
                slots = ip.ttl + 1

        elif isinstance(ip.data, dpkt.icmp.ICMP):
            icmp = ip.data

            if icmp.type == dpkt.icmp.ICMP_TIMEXCEED:
                if not isinstance(icmp.data, dpkt.icmp.ICMP.TimeExceed):
                    continue
                time_exceed = icmp.data

                if not isinstance(time_exceed.data, dpkt.ip.IP):
                    continue
                inner_ip = time_exceed.data

                if not isinstance(inner_ip.data, dpkt.udp.UDP):
                    continue
                inner_udp = inner_ip.data

                # Use the destination port from the inner UDP packet as the sequence number
                seq_no = inner_udp.dport

                if seq_no in samples:
                    samples[seq_no]["reply_ip"] = dpkt.utils.inet_to_str(ip.src)
                    samples[seq_no]["recv_time"] = timestamp

    # Calculate round and rtt
    for sample in samples.values():
        sample["round"] = ((sample["udp_dest_port"] - 1024) // slots) + 1

        if sample["recv_time"] != 0:
            sample["rtt"] = round(1000 * (sample["recv_time"] - sample["send_time"]), 6)

    down_start, down_end, up_start, up_end, server_ip = speedtest_boundaries.preprocess_speedtest(metadata_file, pcap_file, extra_idle_time)
    boundaries = {
        'pcap_file': pcap_file,
        'download_start': down_start,
        'download_end': down_end,
        'upload_start': up_start,
        'upload_end': up_end,
        'server_ip': server_ip
    }

    # Read & update metadata
    with open(metadata_file, "r") as fh:
        data = json.load(fh)
        data["Measurements"]["rtt_samples"] = list(samples.values())
        data["Measurements"]["boundaries"] = boundaries

    # Write metadata
    with open(metadata_out or metadata_file, "w") as fh:
        json.dump(data, fh)

if __name__ == "__main__":
   if len(sys.argv) != 3:
         print("Usage: python pcap_processor.py <metadata_file.json> <pcap_file.pcap>")
         sys.exit(1)
   json_f = sys.argv[1]
   pcap_f = sys.argv[2]
   save_rtt_samples(pcap_f, json_f)
    # Root_dir = 'milwaukee'
    # for sub_dir in os.listdir(Root_dir):
    #     print(sub_dir)
    #     path1 = os.path.join(Root_dir, sub_dir)
    #     for sub_sub_dir in os.listdir(path1):
    #         print(sub_sub_dir)
    #         path2 = os.path.join(path1, sub_sub_dir)
    #         json_path = os.path.join(path2, 'json')
    #         pcap_path = os.path.join(path2, 'pcap')
    #         FOUND_MATCH = False
    #         for f1 in os.listdir(pcap_path):
    #             pcap_dir = os.path.join(pcap_path, f1)
    #             prefix = f1[:-12]
    #             for f_json in os.listdir(json_path):
    #                 if prefix in f_json:
    #                     FOUND_MATCH = True
    #                     json_dir = os.path.join(json_path, f_json)
    #                     save_rtt_samples(pcap_dir, json_dir)
    #                     print(json_dir, f_json)
    #                     break
    
        