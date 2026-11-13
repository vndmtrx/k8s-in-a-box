#!/usr/bin/env python3
"""Extrai um arquivo de uma imagem no formato docker-archive.

Uso: extrai-do-oci.py <imagem.tar> <caminho-na-imagem> <arquivo-de-saida>

Percorre as camadas da mais nova para a mais antiga e grava a primeira
ocorrência do arquivo, como faria o runtime ao montar o container.
"""
import json
import os
import sys
import tarfile

imagem, alvo, saida = sys.argv[1:4]

with tarfile.open(imagem) as pacote:
    camadas = json.load(pacote.extractfile("manifest.json"))[0]["Layers"]
    for nome in reversed(camadas):
        with tarfile.open(fileobj=pacote.extractfile(nome)) as camada:
            try:
                membro = camada.getmember(alvo)
            except KeyError:
                continue
            os.makedirs(os.path.dirname(saida), exist_ok=True)
            with open(saida, "wb") as arquivo:
                arquivo.write(camada.extractfile(membro).read())
            sys.exit(0)

sys.exit(f"Arquivo {alvo} não encontrado em {imagem}")
