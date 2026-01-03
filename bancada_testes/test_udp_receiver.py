#!/usr/bin/env python3
"""
Script de teste simples para receber pacotes UDP na porta 55555
"""
import socket
import sys

UDP_PORT = 55555

print(f"[TEST] Criando socket UDP...")
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

print(f"[TEST] Fazendo bind em 0.0.0.0:{UDP_PORT}...")
try:
    sock.bind(('0.0.0.0', UDP_PORT))
    print(f"[TEST] ✓ Socket ligado com sucesso em 0.0.0.0:{UDP_PORT}")
except Exception as e:
    print(f"[TEST] ✗ ERRO ao fazer bind: {e}")
    sys.exit(1)

print(f"[TEST] Aguardando pacotes UDP...")
print(f"[TEST] Pressione Ctrl+C para parar")
print("-" * 60)

try:
    while True:
        data, addr = sock.recvfrom(65535)
        print(f"[{addr[0]}:{addr[1]}] Recebido {len(data)} bytes:")
        try:
            decoded = data.decode('utf-8')
            print(decoded[:500])  # Primeiros 500 caracteres
        except:
            print(f"  (dados binários: {data[:100]}...)")
        print("-" * 60)
except KeyboardInterrupt:
    print("\n[TEST] Parando...")
finally:
    sock.close()
    print("[TEST] Socket fechado.")

