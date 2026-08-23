#!/usr/bin/python3
import socket
import sys
import time

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(sys.argv[1])
    server.listen(1)
    connection, _ = server.accept()
    with connection:
        request = b""
        while b"\n" not in request:
            chunk = connection.recv(4096)
            if not chunk:
                raise RuntimeError("client closed before sending a request")
            request += chunk
        time.sleep(2)
        connection.sendall(b"update-available: yes\n")
