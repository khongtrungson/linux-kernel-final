#!/bin/bash
# ==============================================================================
# Script kiểm thử đơn vị cho tính năng Quản lý Phần mềm (manage_software)
# Giả lập (Mock) dpkg-query và sudo apt-get để chạy thử nghiệm an toàn.
# ==============================================================================

# Trạng thái giả lập của hệ thống (danh sách các gói đã cài đặt)
MOCK_INSTALLED="git curl"
MOCK_APT_FAIL=0 # Nếu là 1, lệnh apt-get sẽ giả lập lỗi

# Hàm mock cho dpkg-query
dpkg-query() {
    local cmd=$1
    local fmt=$2
    local pkg=$3
    
    if [ "${cmd}" = "-W" ] && [ "${fmt}" = "-f=\${Status}" ]; then
        # Kiểm tra xem gói có trong danh sách giả lập đã cài đặt hay không
        if [[ " ${MOCK_INSTALLED} " =~ " ${pkg} " ]]; then
            echo "install ok installed"
            return 0
        else
            echo "unknown ok not-installed"
            return 1
        fi
    fi
    command dpkg-query "$@"
}

# Hàm mock cho sudo
sudo() {
    if [ "$1" = "apt-get" ]; then
        local action=$2
        local flag=$3
        local pkg=$4
        
        if [ "${MOCK_APT_FAIL}" -eq 1 ]; then
            echo "Mock apt-get failure for package ${pkg}" >&2
            return 100 # Mã lỗi giả lập
        fi
        
        if [ "${action}" = "install" ] && [ "${flag}" = "-y" ]; then
            echo "Mocked installing package: ${pkg}"
            return 0
        elif [ "${action}" = "remove" ] && [ "${flag}" = "-y" ]; then
            echo "Mocked removing package: ${pkg}"
            return 0
        fi
    else
        command sudo "$@"
    fi
}

# Source shell/system_tool.sh
source "$(dirname "$0")/../shell/system_tool.sh"

# Hàm chạy một test case đơn lẻ
run_test() {
    local name=$1
    local input=$2
    local expected=$3
    local out
    
    out=$(echo -e "${input}" | manage_software 2>&1)
    
    if [[ "${out}" =~ "${expected}" ]]; then
        echo -e "[\e[32m PASS \e[0m] ${name}"
        return 0
    else
        echo -e "[\e[31m FAIL \e[0m] ${name}"
        echo "Input: ${input}"
        echo "Expected match: ${expected}"
        echo "Got output: ${out}"
        return 1
    fi
}

# Kịch bản kiểm thử
main_tests() {
    local exit_code=0
    
    echo "--- Khởi chạy các ca kiểm thử cho manage_software ---"
    
    # Test 1: Tên gói rỗng
    run_test "Tên gói rỗng" "" "Lỗi: Tên gói phần mềm không được để trống!" || exit_code=1
    
    # Test 2: Tên gói chứa ký tự không hợp lệ (ngăn chặn Command Injection)
    run_test "Tên gói chứa ký tự độc hại" "htop; rm -rf /" "Lỗi: Tên gói phần mềm không hợp lệ!" || exit_code=1
    run_test "Tên gói chứa dấu cách" "htop git" "Lỗi: Tên gói phần mềm không hợp lệ!" || exit_code=1
    
    # Test 3: Gói chưa cài -> Chọn không cài đặt
    MOCK_INSTALLED="git curl"
    run_test "Gói chưa cài - hủy cài đặt" "htop\nn" "Đã hủy thao tác cài đặt" || exit_code=1
    
    # Test 4: Gói chưa cài -> Chọn đồng ý cài đặt
    MOCK_INSTALLED="git curl"
    run_test "Gói chưa cài - đồng ý cài đặt thành công" "htop\ny" "Mocked installing package: htop" || exit_code=1
    
    # Test 5: Gói đã cài -> Chọn không gỡ bỏ
    MOCK_INSTALLED="git curl"
    run_test "Gói đã cài - hủy gỡ cài đặt" "git\nn" "Đã hủy thao tác gỡ bỏ" || exit_code=1
    
    # Test 6: Gói đã cài -> Chọn đồng ý gỡ bỏ
    MOCK_INSTALLED="git curl"
    run_test "Gói đã cài - đồng ý gỡ bỏ thành công" "git\ny" "Mocked removing package: git" || exit_code=1
    
    # Test 7: Giả lập apt-get lỗi khi cài đặt
    MOCK_INSTALLED="git curl"
    MOCK_APT_FAIL=1
    run_test "Cài đặt lỗi hệ thống" "htop\ny" "Lỗi: Không thể cài đặt gói 'htop'!" || exit_code=1
    MOCK_APT_FAIL=0
    
    # Test 8: Giả lập apt-get lỗi khi gỡ bỏ
    MOCK_INSTALLED="git curl"
    MOCK_APT_FAIL=1
    run_test "Gỡ bỏ lỗi hệ thống" "git\ny" "Lỗi: Không thể gỡ bỏ gói 'git'!" || exit_code=1
    MOCK_APT_FAIL=0
    
    return "${exit_code}"
}

main_tests
exit $?
