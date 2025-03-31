using UnityEngine;

[ExecuteAlways]
[RequireComponent(typeof(Camera))]
public class _SSAA : MonoBehaviour
{
    [Range(1, 4)]
    public int ssaaMultiplier = 2;

    private int lastMultiplier = -1;

    private Camera mainCamera;     // 屏幕显示用主摄像机
    private Camera ssaaCamera;     // 高分采样专用摄像机
    private RenderTexture ssaaRT;  // SSAA 渲染结果图像

    void OnEnable()
    {
        InitializeCameras();
    }

    void Update()
    {
        // 检测倍率是否变化，动态重建 RT
        if (ssaaMultiplier != lastMultiplier)
        {
            Debug.Log($"[SSAA] 采样倍率变化：{lastMultiplier} → {ssaaMultiplier}");
            RebuildRenderTarget();
        }
    }

    void OnDisable()
    {
        CleanupResources();
    }

    /// 初始化主摄像机与 SSAA 采样摄像机
    void InitializeCameras()
    {
        mainCamera = GetComponent<Camera>();

        // 清除旧的 SSAA 摄像机（如果存在）
        Transform existing = transform.Find("SSAA Camera");
        if (existing != null)
        {
            DestroyImmediate(existing.gameObject);
        }

        // 创建新摄像机作为 SSAA 用
        GameObject ssaaCamObj = new GameObject("SSAA Camera");
        ssaaCamObj.transform.SetParent(transform, false);

        ssaaCamera = ssaaCamObj.AddComponent<Camera>();
        CopyCameraSettings(mainCamera, ssaaCamera);
        ssaaCamera.enabled = false;

        // 初次创建 RenderTexture
        RebuildRenderTarget();
    }

    /// 复制主摄像机的设置到 SSAA 摄像机
    void CopyCameraSettings(Camera source, Camera target)
    {
        target.CopyFrom(source);
        target.clearFlags = source.clearFlags;
        target.cullingMask = source.cullingMask;
        target.depth = source.depth - 1; // 保证主摄后渲染
    }

    /// 重建 SSAA 使用的高分辨率 RenderTexture
    void RebuildRenderTarget()
    {
        lastMultiplier = ssaaMultiplier;

        // 释放旧资源
        if (ssaaRT != null)
        {
            if (RenderTexture.active == ssaaRT)
                RenderTexture.active = null;

            ssaaRT.Release();
            DestroyImmediate(ssaaRT);
        }

        int width = Screen.width * ssaaMultiplier;
        int height = Screen.height * ssaaMultiplier;

        ssaaRT = new RenderTexture(width, height, 24, RenderTextureFormat.DefaultHDR);
        ssaaRT.Create();

        ssaaCamera.targetTexture = ssaaRT;
    }

    /// 渲染完成后将 SSAA 图像缩小输出到屏幕
    void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        if (ssaaCamera == null || ssaaRT == null)
        {
            Graphics.Blit(src, dest);
            return;
        }

        ssaaCamera.Render();           // 渲染高分图像
        Graphics.Blit(ssaaRT, dest);   // 缩放输出到屏幕
    }

    /// 清理资源，防止内存泄漏
    void CleanupResources()
    {
        if (ssaaCamera != null)
        {
            DestroyImmediate(ssaaCamera.gameObject);
            ssaaCamera = null;
        }

        if (ssaaRT != null)
        {
            ssaaRT.Release();
            DestroyImmediate(ssaaRT);
            ssaaRT = null;
        }
    }
}
