#!/usr/bin/env bash
# ==============================================================================
# WorkBuddy2API-Hub 一键安装与快速更新脚本
# 首次部署: curl -fsSL https://raw.githubusercontent.com/RoninXj/workbuddy2api-hub/main/quick-deploy.sh | bash
# 快速更新: 再跑一次同一条命令（拉最新镜像 → 重建容器，账号配置绝不丢失）
# 部署模式: WB_DEPLOY_MODE=local|lan|public（默认 lan）
# 本地构建: WB_BUILD=1（不走 GHCR，从源码 tarball 构建，需要能拉 golang/python 基础镜像）
# 换镜像:   WB_IMAGE=ghcr.io/xxx/workbuddy2api-hub:latest
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ---- 镜像与源码来源（全部可用环境变量覆盖）----
IMAGE="${WB_IMAGE:-ghcr.io/roninxj/workbuddy2api-hub:latest}"
SRC_TARBALL="${WB_SRC_TARBALL:-https://github.com/RoninXj/workbuddy2api-hub/archive/refs/heads/main.tar.gz}"
WB_BUILD="${WB_BUILD:-0}"

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${GREEN}   WorkBuddy2API-Hub Docker 一键部署与更新脚本${NC}"
echo -e "${BLUE}======================================================${NC}\n"

# 0. 部署模式
DEPLOY_MODE="${WB_DEPLOY_MODE:-lan}"
case "${DEPLOY_MODE}" in
    local|lan|public) ;;
    *)
        echo -e "${RED}[错误] WB_DEPLOY_MODE 只能是 local / lan / public，当前为: ${DEPLOY_MODE}${NC}"
        exit 1
        ;;
esac
if [ "${DEPLOY_MODE}" = "lan" ]; then
    PORT_BINDING="8788:8788"
else
    PORT_BINDING="127.0.0.1:8788:8788"
fi
echo -e "${BLUE}[信息] 部署模式: ${DEPLOY_MODE}（端口映射 ${PORT_BINDING}）${NC}"
echo -e "${BLUE}[信息] 目标镜像: ${IMAGE}${NC}"

# 1. 检查 Docker 环境
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[错误] 未检测到 Docker，请先安装 Docker 后再运行此脚本。${NC}"
    exit 1
fi
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}[错误] 未检测到 Docker Compose 支持 (docker compose / docker-compose)。${NC}"
    exit 1
fi

# 2. 确定工作目录
APP_DIR="workbuddy2api-hub"
if [ -f "docker-compose.yml" ] && grep -q "wb-proxy" docker-compose.yml 2>/dev/null; then
    TARGET_DIR="$(pwd)"
    echo -e "${BLUE}[信息] 在当前目录检测到项目配置: ${TARGET_DIR}${NC}"
else
    TARGET_DIR="$(pwd)/${APP_DIR}"
    if [ ! -d "${TARGET_DIR}" ]; then
        echo -e "${BLUE}[信息] 创建安装目录: ${TARGET_DIR}${NC}"
        mkdir -p "${TARGET_DIR}"
    fi
    cd "${TARGET_DIR}"
fi

pull_or_die() {
    if ! $COMPOSE_CMD pull; then
        echo -e "${RED}[错误] 拉取 ${IMAGE} 被仓库拒绝（denied）：该镜像还没发布，或 GHCR 包仍是私有。${NC}"
        echo -e "${YELLOW}排查顺序：${NC}"
        echo -e "  1) 仓库 Actions 是否跑成功过（Publish Docker image 最新一次是绿的？fork 仓库要先手动启用 Actions）"
        echo -e "  2) 包可见性是否为 Public（GitHub → Your packages → workbuddy2api-hub → Package settings → Change visibility）"
        echo -e "  3) 先用上面那条 token/manifest 探针确认返回 200"
        echo -e "  4) 不想等镜像：WB_BUILD=1 重跑本脚本，从源码在本机构建"
        exit 1
    fi
}

# 3. 首次安装 vs 更新
if [ -f "docker-compose.yml" ]; then
    echo -e "${YELLOW}[升级模式] 检测到已有部署，正在更新容器...${NC}"
    if [ -n "${WB_DEPLOY_MODE:-}" ]; then
        echo -e "${YELLOW}[提示] 已有部署不会自动改写端口映射；如需限制监听地址，请手动编辑 docker-compose.yml 的 ports。${NC}"
    fi
    # 把老 compose 里的 image 行对齐到 IMAGE（ports / volumes 原样保留）
    if grep -q '^[[:space:]]*image:' docker-compose.yml; then
        sed -i.bak 's#^\([[:space:]]*image:\).*#\1 '"${IMAGE}"'#' docker-compose.yml
        echo -e "${BLUE}[信息] docker-compose.yml 的 image 已对齐（备份 docker-compose.yml.bak）${NC}"
    fi
    if [ "${WB_BUILD}" = "1" ]; then
        echo -e "${BLUE}[构建模式] 从源码构建 ${IMAGE}${NC}"
        rm -rf "${TARGET_DIR}/.src"; mkdir -p "${TARGET_DIR}/.src"
        curl -fsSL "${SRC_TARBALL}" | tar xz -C "${TARGET_DIR}/.src" --strip-components=1
        docker build -t "${IMAGE}" "${TARGET_DIR}/.src"
    else
        pull_or_die
    fi
    $COMPOSE_CMD up -d
    echo -e "\n${GREEN}[成功] WorkBuddy2API-Hub 已更新到最新版本！${NC}"
else
    echo -e "${BLUE}[安装模式] 正在进行首次初始化部署...${NC}"
    cat > docker-compose.yml << EOF
services:
  wb-proxy:
    image: ${IMAGE}
    container_name: wb-proxy
    restart: unless-stopped
    ports:
      - "${PORT_BINDING}"
    environment:
      - HOST=0.0.0.0
      - PORT=8788
      # - API_KEY=your_secret_key
      - TZ=Asia/Shanghai
    volumes:
      - ./accounts:/app/accounts
      - ./usage:/app/usage
EOF
    mkdir -p accounts usage
    if [ "${WB_BUILD}" = "1" ]; then
        echo -e "${BLUE}[构建模式] 从源码构建 ${IMAGE}${NC}"
        rm -rf "${TARGET_DIR}/.src"; mkdir -p "${TARGET_DIR}/.src"
        curl -fsSL "${SRC_TARBALL}" | tar xz -C "${TARGET_DIR}/.src" --strip-components=1
        docker build -t "${IMAGE}" "${TARGET_DIR}/.src"
    else
        echo -e "${BLUE}[信息] 正在拉取镜像...${NC}"
        pull_or_die
    fi
    $COMPOSE_CMD up -d
    echo -e "\n${GREEN}[成功] WorkBuddy2API-Hub 首次部署成功！${NC}"
fi

# 4. 输出引导提示
LOCAL_IP="127.0.0.1"
if command -v hostname >/dev/null 2>&1; then
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
fi
if [ "${DEPLOY_MODE}" = "lan" ]; then
    SHOW_HOST="${LOCAL_IP:-127.0.0.1}"
else
    SHOW_HOST="127.0.0.1"
fi
echo -e "\n${BLUE}------------------------------------------------------${NC}"
echo -e "${GREEN}Web 控制看板:${NC} http://${SHOW_HOST}:8788"
echo -e "${GREEN}OpenAI 接口:${NC}  http://${SHOW_HOST}:8788/v1"
if [ "${DEPLOY_MODE}" = "public" ]; then
    echo -e "${YELLOW}公网部署:${NC} 8788 只绑在本机回环地址，请用 Nginx / Caddy / Cloudflare Tunnel 反代并加 TLS。"
fi
echo -e "${BLUE}------------------------------------------------------${NC}"
echo -e "${YELLOW}查看初始 API Key:${NC}  $COMPOSE_CMD logs wb-proxy | grep -i 'api key'"
echo -e "${YELLOW}查看实时运行日志:${NC}  $COMPOSE_CMD logs -f wb-proxy"
echo -e "${YELLOW}后续如何更新:${NC}      再跑一次同一条 curl 命令即可"
if [ "${WB_BUILD}" = "1" ]; then
    echo -e "${YELLOW}注意:${NC} 本次是本地构建模式，迁移/重装请在命令前带上 WB_BUILD=1"
fi
echo -e "${BLUE}======================================================${NC}\n"
