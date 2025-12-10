import sys
log_file = open('extract_psd_log.txt', 'w', encoding='utf-8')

def log(msg):
    log_file.write(msg + '\n')
    log_file.flush()

try:
    log('开始处理...')
    from psd_tools import PSDImage
    from PIL import Image
    import os

    # 打开 PSD 文件
    psd_path = r'D:\OneDrive\桌面\not_available_202512080504_34125.psd'
    log(f'打开文件: {psd_path}')
    
    if not os.path.exists(psd_path):
        log(f'错误: 文件不存在!')
        sys.exit(1)
    
    psd = PSDImage.open(psd_path)

    log(f'PSD 尺寸: {psd.width} x {psd.height}')
    log(f'图层数量: {len(psd)}')

    # 列出所有图层
    for i, layer in enumerate(psd):
        log(f'图层 {i}: {layer.name}, 可见: {layer.visible}, 类型: {layer.kind}')

    # 合成整个 PSD 为图像
    log('合成图像...')
    composite = psd.composite()

    # 转换为 RGBA
    if composite.mode != 'RGBA':
        composite = composite.convert('RGBA')

    # 将黑色/深色改成灰色 (#9CA3AF = RGB 156, 163, 175)
    # 使用 numpy 加速处理
    log('转换颜色 (使用 numpy 加速)...')
    import numpy as np
    
    # 转换为 numpy 数组
    img_array = np.array(composite)
    
    # 分离通道
    r, g, b, a = img_array[:,:,0], img_array[:,:,1], img_array[:,:,2], img_array[:,:,3]
    
    # 计算亮度
    brightness = (r.astype(np.float32) + g + b) / 3
    
    # 找到深色且不透明的像素
    mask = (brightness < 128) & (a > 0)
    
    # 替换为灰色
    img_array[mask, 0] = 156  # R
    img_array[mask, 1] = 163  # G
    img_array[mask, 2] = 175  # B
    
    # 转回 PIL Image
    composite = Image.fromarray(img_array)
    log('颜色转换完成')

    # 保存到项目资源目录
    output_path = r'E:\projects\qemu-hmos\entry\src\main\resources\base\media\not_available.png'
    log(f'保存到: {output_path}')
    composite.save(output_path, 'PNG')
    log('完成!')
except Exception as e:
    log(f'错误: {e}')
    import traceback
    log(traceback.format_exc())
finally:
    log_file.close()

