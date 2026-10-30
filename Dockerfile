# Dockerfile
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ComfyUI

# 再現性のため、検証が固まったらコミットハッシュを指定する
ARG COMFY_REF=master
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . && git checkout ${COMFY_REF}

# torchは先に公式CUDAビルドで入れる（requirements.txtが汎用版を入れないように）
# RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
RUN pip install torch==2.11.0 torchvision==0.26.0 torchaudio==2.11.0 --index-url https://download.pytorch.org/whl/cu130
RUN pip install -r requirements.txt
RUN pip install -r manager_requirements.txt

# llama-cpp-python（CUDA 13.0 ビルド済み wheel）。--no-deps で入れ、不足する diskcache だけ足す
# numpy は llama-cpp-python の要求（<=2.3.2）に合わせて固定する（ローカル環境でもこの版でないと動かなかった）
RUN pip install --no-deps "https://github.com/JamePeng/llama-cpp-python/releases/download/v0.4.5-cu130-linux-20261025/llama_cpp_python-0.4.5+cu130-cp312-cp312-linux_x86_64.whl" \
 && pip install "diskcache>=5.6.2" "numpy==2.3.2"

# Install cv2 for ComfyUI-Easy-Use
# GUI 版の opencv-python は libGL などを要求し、slim イメージでは import に失敗するため headless 版を使う
RUN pip install opencv-python-headless

# ComfyUI Nvidia VFX Nodes 用。PyPI の nvidia-vfx はスタブで、実体の wheel は NVIDIA のインデックスにある
RUN pip install --extra-index-url https://pypi.nvidia.com "nvidia-vfx>=0.2"

# Load BalancerのヘルスチェックはHEALTH_CHECK_PATHを無視して常に /ping を叩くため、
# ComfyUIのフロントエンド静的ディレクトリに ping ファイルを置いて 200 を返させる
RUN python -c "import comfyui_frontend_package as p, os; \
f=os.path.join(os.path.dirname(p.__file__),'static','ping'); open(f,'w').write('ok'); print(f)"

# Network Volume（/runpod-volume）上のモデルを参照する設定
# ComfyUIはルート直下の extra_model_paths.yaml を起動時に自動で読み込む
COPY extra_model_paths.yaml /ComfyUI/extra_model_paths.yaml

EXPOSE 8188

# output / input / user を Network Volume に置き、ワーカー停止後も残す
# --user-directory は存在しないパスだと起動時にエラー終了するため、先に作成してから起動する
CMD ["bash", "-c", "mkdir -p /runpod-volume/ComfyUI/output /runpod-volume/ComfyUI/input /runpod-volume/ComfyUI/user /runpod-volume/ComfyUI/custom_nodes /runpod-volume/ComfyUI/models/LLM && cd /ComfyUI && exec python main.py --listen 0.0.0.0 --port 8188 --output-directory /runpod-volume/ComfyUI/output --input-directory /runpod-volume/ComfyUI/input --user-directory /runpod-volume/ComfyUI/user --enable-manager"]
