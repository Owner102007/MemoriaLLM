#!/usr/bin/env python3
"""SHA-256 сертификата, которым подписан APK (SNO-F-REC-13).

    python3 tool/apk_cert_sha256.py out/memoria-sno2026-I.apk

Печатает отпечаток сертификата первого подписавшего из каждого блока
подписи (схемы v2, v3, v3.1) — строчными шестнадцатеричными знаками,
по строке на блок. У APK без блока подписи не печатает ничего.

Зачем свой разбор: шаг CI «Чем подписан APK» сверяет подпись сборок
ветвей с ключом владельца, а вывод `apksigner` меняется от версии к
версии инструментов сборки: до 36-й — «Signer #1 certificate SHA-256
digest», с 37-й — «V2 Signer: certificate SHA-256 digest». На этом шаг
уже падал (прогон №255, вторая попытка), а логи шагов сессии
разработки недоступны. Формат самого блока подписи описан в
документации Android («APK Signature Scheme v2») и от версии
инструментов не зависит. `apksigner` в шаге остаётся вторым мнением.

Подпись здесь не проверяется — только читается, чей сертификат в неё
вложен: проверяет подпись сам Android при установке, а шагу CI нужно
знать, тем ли ключом подписала сборка.
"""

import hashlib
import struct
import sys

MAGIC = b'APK Sig Block 42'
SCHEMES = {0x7109871A: 'v2', 0xF05368C0: 'v3', 0x1B93AD61: 'v3.1'}


def prefixed(data, at):
    """Кусок с длиной впереди (uint32) и место сразу за ним."""
    (size,) = struct.unpack_from('<I', data, at)
    if at + 4 + size > len(data):
        raise ValueError('длина куска выходит за блок подписи')
    return data[at + 4:at + 4 + size], at + 4 + size


def signing_block(path):
    """Пары блока подписи APK; `None` — блока нет."""
    with open(path, 'rb') as apk:
        apk.seek(0, 2)
        end = apk.tell()
        # Конец оглавления ZIP — в последних 64 КБ файла.
        tail = min(end, 65557)
        apk.seek(end - tail)
        buffer = apk.read(tail)
        eocd = buffer.rfind(b'PK\x05\x06')
        if eocd < 0 or eocd + 20 > len(buffer):
            return None
        (directory,) = struct.unpack_from('<I', buffer, eocd + 16)
        if directory < 32:
            return None
        # Блок подписи стоит вплотную перед оглавлением и кончается
        # своей длиной и словом-меткой.
        apk.seek(directory - 24)
        foot = apk.read(24)
        if foot[8:] != MAGIC:
            return None
        (size,) = struct.unpack_from('<Q', foot, 0)
        if size < 24 or size + 8 > directory:
            return None
        apk.seek(directory - size - 8)
        return apk.read(size + 8)[8:-24]


def certificates(path):
    """(схема, отпечаток) первого подписавшего в каждом блоке подписи."""
    pairs = signing_block(path)
    found = []
    at = 0
    while pairs and at + 12 <= len(pairs):
        (size,) = struct.unpack_from('<Q', pairs, at)
        (ident,) = struct.unpack_from('<I', pairs, at + 8)
        if size < 4 or at + 8 + size > len(pairs):
            raise ValueError('пара блока подписи выходит за блок')
        value = pairs[at + 12:at + 8 + size]
        at += 8 + size
        if ident not in SCHEMES:
            continue
        # подписавшие → первый → подписанные данные → (суммы,
        # сертификаты, …) → первый сертификат.
        signers, _ = prefixed(value, 0)
        signer, _ = prefixed(signers, 0)
        signed, _ = prefixed(signer, 0)
        _, after_digests = prefixed(signed, 0)
        chain, _ = prefixed(signed, after_digests)
        certificate, _ = prefixed(chain, 0)
        found.append((SCHEMES[ident], hashlib.sha256(certificate).hexdigest()))
    return found


def main(argv):
    if len(argv) != 2:
        print('нужен один путь к APK', file=sys.stderr)
        return 2
    try:
        found = certificates(argv[1])
    except (OSError, ValueError, struct.error) as error:
        print(f'{argv[1]}: блок подписи не читается: {error}',
              file=sys.stderr)
        return 1
    for scheme, digest in found:
        print(digest)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
