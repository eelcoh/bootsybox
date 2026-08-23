#!/usr/bin/python3
import socket
import sys
import time

result = int(sys.argv[2]) if len(sys.argv) > 2 else 0

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(sys.argv[1])
    server.listen(1)
    connection, _ = server.accept()
    with connection:
        connection.sendall(b"__BOOTSYBOX_PROTOCOL__ 1\n")
        request = b""
        while b"\n" not in request:
            chunk = connection.recv(4096)
            if not chunk:
                raise RuntimeError("client closed before sending a request")
            request += chunk
        time.sleep(2)
        if result == 0:
            connection.sendall(b"update-available: yes\n")
        else:
            connection.sendall(b"error: candidate is incompatible\n")
        connection.sendall(f"__BOOTSYBOX_RESULT__ {result}\n".encode())
