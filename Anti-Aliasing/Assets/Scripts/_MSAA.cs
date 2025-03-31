using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class _MSAA : MonoBehaviour
{
    public enum MSAALevel
    {
        Disabled = 0,
        MSAA2x = 2,
        MSAA4x = 4,
        MSAA8x = 8
    }

    public MSAALevel MSAAQuality = MSAALevel.MSAA2x;
    // Update is called once per frame
    void Update()
    {
        QualitySettings.antiAliasing = (int)MSAAQuality;
    }
}
