#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import os
from datetime import datetime, timezone

DEFAULT_ALLOW_HOSTS = (
    "api.openai.com",
    "auth.openai.com",
    "chatgpt.com",
    "ab.chatgpt.com",
    "persistent.oaistatic.com",
)


def allowed_hosts(args: argparse.Namespace) -> set[str]:
    env_hosts = os.environ.get("OPENAI_EGRESS_DOMAINS", "")
    return {host.lower() for host in [*DEFAULT_ALLOW_HOSTS, *args.allow_host, *env_hosts.split()] if host}


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    while data := await reader.read(65536):
        writer.write(data)
        await writer.drain()
    writer.close()


async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, hosts: set[str]) -> None:
    peer = writer.get_extra_info("peername")
    line = await reader.readline()
    parts = line.decode("ascii", errors="replace").strip().split()
    if len(parts) != 3 or parts[0].upper() != "CONNECT":
        writer.write(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
        await writer.drain()
        writer.close()
        return
    host, port = parts[1].rsplit(":", 1)
    if host.lower() not in hosts or port != "443":
        writer.write(b"HTTP/1.1 403 Forbidden\r\n\r\n")
        await writer.drain()
        writer.close()
        print(f"{timestamp()} deny peer={peer} target={parts[1]}", flush=True)
        return
    while (await reader.readline()) not in {b"\r\n", b"\n", b""}:
        pass
    upstream_reader, upstream_writer = await asyncio.open_connection(host, int(port))
    writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
    await writer.drain()
    print(f"{timestamp()} allow peer={peer} target={parts[1]}", flush=True)
    await asyncio.gather(pipe(reader, upstream_writer), pipe(upstream_reader, writer), return_exceptions=True)


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


async def main_async(args: argparse.Namespace) -> None:
    hosts = allowed_hosts(args)
    server = await asyncio.start_server(lambda r, w: handle(r, w, hosts), args.host, args.port)
    print(f"{timestamp()} listening host={args.host} port={args.port} allow={','.join(sorted(hosts))}", flush=True)
    async with server:
        await server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description="Tiny CONNECT proxy that only permits OpenAI/Codex hostnames")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--allow-host", action="append", default=[])
    asyncio.run(main_async(parser.parse_args()))


if __name__ == "__main__":
    main()
