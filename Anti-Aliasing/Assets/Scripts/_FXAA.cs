using UnityEngine;
using System;
using UnityEngine.Rendering;

// 编辑器下也能运行
// 允许后处理效果在SCENE视图中也生效
[ExecuteInEditMode, ImageEffectAllowedInSceneView]

public class _FXAA : MonoBehaviour
{
    public enum FXAAMode{
        Quality = 0,        //高质量
        Console = 1,        //高性能
    };

    public FXAAMode mode;

    // 对比度阈值
    // - 边缘像素必须超过该值才会被当作锯齿处理
    [Range(0.0312f, 0.0833f)]

    public float contrastThreshold = 0.0312f;
    // 相对阈值（处理强度）
    // - 控制边缘强度相对邻域的变化
    [Range(0.063f, 0.333f)]
    public float relativeThreshold = 0.063f;

    public Shader fxaaShader;
    [NonSerialized]
    private Material fxaaMaterial;  // 运行时的临时Material

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if(fxaaMaterial == null){
            fxaaMaterial = new Material(fxaaShader);
            fxaaMaterial.hideFlags = HideFlags.HideAndDontSave;
        }

        fxaaMaterial.SetFloat("_ContrastThreshold", contrastThreshold);
        fxaaMaterial.SetFloat("_RelativeThreshold", relativeThreshold);

        // - Pass 0 是高质量
        // - Pass 1 是高性能
        Graphics.Blit(source, destination, fxaaMaterial, (int)mode);

    }

}