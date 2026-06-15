#!/bin/bash
# Test file for set_system_time

# Mock date command for setting time, but let validation -d pass through to real command
date() {
    if [ "$1" = "-s" ]; then
        echo "Mocked setting time to: $2"
        return 0
    elif [ "$1" = "+%Y-%m-%d %H:%M:%S" ]; then
        echo "2026-06-16 12:00:00"
        return 0
    else
        command date "$@"
    fi
}

set_system_time() {
    local datetime_str
    
    echo "-----------------------------------------"
    echo "         CẤU HÌNH GIỜ HỆ THỐNG          "
    echo "-----------------------------------------"
    read -p "Nhập chuỗi ngày giờ (định dạng YYYY-MM-DD HH:MM:SS): " datetime_str
    
    if [ -z "${datetime_str}" ]; then
        echo "Lỗi: Chuỗi ngày giờ không được để trống!"
        return 1
    fi
    
    # Kiểm tra định dạng bằng regex
    if [[ ! "${datetime_str}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        echo "Lỗi: Ngày giờ nhập vào sai định dạng YYYY-MM-DD HH:MM:SS!"
        return 1
    fi
    
    # Kiểm tra tính hợp lệ logic của ngày giờ bằng date -d
    if ! date -d "${datetime_str}" &>/dev/null; then
        echo "Lỗi: Ngày giờ không hợp lệ!"
        return 1
    fi
    
    # Cập nhật thời gian hệ thống bằng date -s
    date -s "${datetime_str}" > /dev/null
    if [ $? -eq 0 ]; then
        echo "Cập nhật thời gian hệ thống thành công!"
        echo "Thời gian hiện tại: $(date '+%Y-%m-%d %H:%M:%S')"
    else
        echo "Lỗi: Không thể cập nhật thời gian hệ thống!"
        return 1
    fi
}

# Run tests
test_invalid_format() {
    local out
    # Mock input "2026-06-16"
    out=$(echo "2026-06-16" | set_system_time 2>&1)
    if [[ ! "${out}" =~ "sai định dạng" ]]; then
        echo "Test failed: '2026-06-16' did not trigger format error. Got: ${out}"
        return 1
    fi
    echo "Test passed: '2026-06-16' correctly failed format validation"
}

test_invalid_logic() {
    local out
    # Mock input "2026-02-30 12:00:00"
    out=$(echo "2026-02-30 12:00:00" | set_system_time 2>&1)
    if [[ ! "${out}" =~ "không hợp lệ" ]]; then
        echo "Test failed: '2026-02-30 12:00:00' did not trigger logic error. Got: ${out}"
        return 1
    fi
    echo "Test passed: '2026-02-30 12:00:00' correctly failed logic validation"
}

test_valid_datetime() {
    local out
    # Mock input "2026-06-16 12:00:00"
    out=$(echo "2026-06-16 12:00:00" | set_system_time 2>&1)
    if [[ ! "${out}" =~ "Cập nhật thời gian hệ thống thành công" ]]; then
        echo "Test failed: '2026-06-16 12:00:00' should have succeeded. Got: ${out}"
        return 1
    fi
    echo "Test passed: '2026-06-16 12:00:00' correctly updated system time"
}

# Run the tests
test_invalid_format || exit 1
test_invalid_logic || exit 1
test_valid_datetime || exit 1
echo "All tests passed!"
