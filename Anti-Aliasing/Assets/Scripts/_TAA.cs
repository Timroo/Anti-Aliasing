using UnityEngine;

[ExecuteInEditMode,ImageEffectAllowedInSceneView]
public class _TAA : MonoBehaviour
{
    // 实现TAA的Shader
    public Shader taaShader;
    private Material taaMaterial;
    public Material material{
        get{
            if(taaMaterial == null){
                if(taaShader == null) return null;
                taaMaterial = new Material(taaShader);
            }
            return taaMaterial;
        }
    }

    // 主摄像机
    private Camera m_Camera;
    public new Camera camera{
        get{
            if(m_Camera == null)
                m_Camera = GetComponent<Camera>();
            return m_Camera;
        }
    }

    private int FrameCount = 0;
    private Vector2 _Jitter;
    bool m_ResetHistory = true;
    // 双缓冲保存历史帧
    private RenderTexture[] m_HistoryTextures = new RenderTexture[2];

    // 抖动用Halton序列（8帧周期）
    private Vector2[] HaltonSequence = new Vector2[]
    {
        new Vector2(0.5f, 1.0f / 3),
        new Vector2(0.25f, 2.0f / 3),
        new Vector2(0.75f, 1.0f / 9),
        new Vector2(0.125f, 4.0f / 9),
		new Vector2(0.625f, 7.0f / 9),
		new Vector2(0.375f, 2.0f / 9),
		new Vector2(0.875f, 5.0f / 9),
		new Vector2(0.0625f, 8.0f / 9),
    };

    private void OnEnable()
    {
        // 深度图 | 运动矢量图
        camera.depthTextureMode = DepthTextureMode.Depth | DepthTextureMode.MotionVectors;
        camera.useJitteredProjectionMatrixForTransparentRendering = true;
    }

    // 注入Halton抖动
    // OnPreCull()在摄像机开始剔除（Culling）前执行的
    private void OnPreCull()
    {
        // 1. 先保存一份“未抖动”的投影矩阵（用于透明物体、TAA比较）
        var proj = camera.projectionMatrix;
        camera.nonJitteredProjectionMatrix = proj;

        // 2. 使用 Halton 序列为当前帧生成一个抖动偏移量（周期为 8 帧）
        FrameCount++;
        var Index = FrameCount % 8;
        _Jitter = new Vector2(
            (HaltonSequence[Index].x - 0.5f) / camera.pixelWidth,
            (HaltonSequence[Index].y - 0.5f) / camera.pixelHeight);
        
        // 3. 注入抖动到投影矩阵 m02 / m12 → X / Y 偏移
        proj.m02 += _Jitter.x * 2;
        proj.m12 += _Jitter.y * 2;
        camera.projectionMatrix = proj;
    }

    // 清除抖动
    // OnPostRender()摄像机准备渲染前
    private void OnPostRender()
    {
        // OnPostRender()不能手动修改投影矩阵了，只能恢复
        // 恢复投影矩阵，防止影响其他对象（例如 Unity 编辑器渲染）
        camera.ResetProjectionMatrix();
    }

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        // 1.历史图像缓存读取
        var historyRead = m_HistoryTextures[FrameCount % 2];
        if(historyRead == null || historyRead.width != Screen.width || historyRead.height != Screen.height)
        {
            if(historyRead) RenderTexture.ReleaseTemporary(historyRead);
            historyRead = RenderTexture.GetTemporary(Screen.width, Screen.height, 0, RenderTextureFormat.ARGBHalf);
            m_HistoryTextures[FrameCount % 2] = historyRead;
            m_ResetHistory = true; // 首帧初始化历史帧
        }

        // 2.当前帧写入缓存（用于下一帧）
        var historyWrite = m_HistoryTextures[(FrameCount + 1) % 2];
        if(historyWrite == null || historyWrite.width != Screen.width || historyWrite.height != Screen.height){
            if(historyWrite) RenderTexture.ReleaseTemporary(historyWrite);
            historyWrite = RenderTexture.GetTemporary(Screen.width, Screen.height, 0, RenderTextureFormat.ARGBHalf);
            m_HistoryTextures[(FrameCount + 1) % 2] = historyWrite;
        }

        // 3. 设置Shader参数
        material.SetVector("_Jitter", _Jitter);
        material.SetTexture("_HistoryTex", historyRead);
        material.SetInt("_IgnoreHistory", m_ResetHistory ? 1 : 0);

        // 4. 执行 TAA 图像混合
        // - 由于RenderTexture的特性，它是引用类型对象
        // - 在historyWrite变化时，m_HistoryTextures[(FrameCount + 1) % 2]也会变化
        Graphics.Blit(source, historyWrite, material, 0);
        Graphics.Blit(historyWrite, destination);// 输出到屏幕

        m_ResetHistory = false;
    }














}
