Shader "_TAA"{
    Properties{
        _MainTex("Texture", 2D) = "white" {}
    }
    HLSLINCLUDE
        #pragma exclude_renderers gles
        #include "StdLib.hlsl"
        #include "Colors.hlsl"

        Texture2D _MainTex;                     //当前帧渲染图像
        float4 _MainTex_TexelSize;
        Texture2D _HistoryTex;                  //上一帧渲染图像
        Texture2D _CameraDepthTexture;          //深度图
        float4 _CameraDepthTexture_TexelSize;
        Texture2D _CameraMotionVectorsTexture;  //运动向量图
        float4 _CameraMotionVectorsTexture_TexelSize;
        int _IgnoreHistory;                     //是否忽略历史数据
    
        // 分别用于线性插值采样和点采样
        // - HLSL内置的控制纹理采样行为的对象
        SamplerState sampler_LinearClamp;            
        SamplerState sampler_PointClamp;        

        float2 _Jitter; // 抖动偏移

        struct a2v
        {
            float3 vertex : POSITION;
            float2 uv : TEXCOORD0;
        };

        struct v2f
        {
            float4 vertex : SV_POSITION;
            float2 texcoord : TEXCOORD0;
        };

        v2f Vert(a2v v)
        {
            v2f o;
            // MVP
            o.vertex = mul(unity_MatrixVP, mul(unity_ObjectToWorld, float4(v.vertex, 1.0)));
            o.texcoord = v.uv;
            return o; 
        }

    ENDHLSL

    SubShader{
        Cull Off ZWrite Off ZTest Always
        Pass{
            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment Frag
                // 3×3 像素邻域偏移数组
                static const int2 kOffsets3x3[9] = {
                    int2(-1, -1),int2( 0, -1),int2( 1, -1),
	                int2(-1,  0),int2( 0,  0),int2( 1,  0),
	                int2(-1,  1),int2( 0,  1),int2( 1,  1),
                };

                // 选出领域中最靠近相机的点
                float2 GetClosestFragment(float2 uv){
                    float2 k = _CameraDepthTexture_TexelSize.xy;
                    // 4个角落
                    const float4 neighborhood = float4(
                        SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, UnityStereoClamp(uv - k)),
                        SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, UnityStereoClamp(uv + float2(k.x, -k.y))),
                        SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, UnityStereoClamp(uv + float2(-k.x, k.y))),
                        SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, UnityStereoClamp(uv + k))
                    );
                    #if UNITY_REVERSED_Z
                        #define COMPARE_DEPTH(a, b) step(b, a)
                    #else
                        #define COMPARE_DEPTH(a, b) step(a, b)
                    #endif
                    // 读取当前像素中心深度
                    float3 result = float3(0.0, 0.0, SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv));
                    // 依次比较4角深度，选出最靠近相机的
                    // - 把对应角落的偏移 (±1, ±1) 记录到 result.xy
                    result = lerp(result, float3(-1.0, -1.0, neighborhood.x), COMPARE_DEPTH(neighborhood.x, result.z));
                    result = lerp(result, float3( 1.0, -1.0, neighborhood.y), COMPARE_DEPTH(neighborhood.y, result.z));
                    result = lerp(result, float3(-1.0,  1.0, neighborhood.z), COMPARE_DEPTH(neighborhood.z, result.z));
                    result = lerp(result, float3( 1.0,  1.0, neighborhood.w), COMPARE_DEPTH(neighborhood.w, result.z));
                    return (uv + result.xy * k);
                }

                // 色彩空间转换
                float3 RGBToYCoCg(float3 RGB){
                    float Y = dot(RGB, float3(1,2,1));
                    float Co = dot(RGB, float3(2,0,-2));
                    float Cg = dot(RGB, float3(-1,2,-1));
                    float3 YCoCg = float3( Y, Co, Cg );
                    return YCoCg;
                }
                float3 YCoCgToRGB( float3 YCoCg )
                {
	                float Y  = YCoCg.x * 0.25;
	                float Co = YCoCg.y * 0.25;
	                float Cg = YCoCg.z * 0.25;
	                float R = Y + Co - Cg;
	                float G = Y + Cg;
	                float B = Y - Co - Cg;
	                float3 RGB = float3( R, G, B );
	                return RGB;
                }
                
                // 历史颜色裁剪
                float3 ClipHistory(float3 History, float3 BoxMin, float3 BoxMax){
                    float3 Filtered = (BoxMin + BoxMax) * 0.5f;
                    float3 RayOrigin = History;
                    float3 RayDir = Filtered - History;
                    // 避免RayDir为0
                    RayDir = abs(RayDir) < (1.0/65536.0) ? (1.0/65536.0) : RayDir;
                    float3 InvRayDir = rcp(RayDir);

                    // 判断是否相交
                    float3 MinIntersect = (BoxMin - RayOrigin) * InvRayDir;
                    float3 MaxIntersect = (BoxMax - RayOrigin) * InvRayDir;
                    float3 EnterIntersect = min(MinIntersect, MaxIntersect);
                    float3 ClipBlend = max(EnterIntersect.x, max(EnterIntersect.y, EnterIntersect.z));
                    ClipBlend = saturate(ClipBlend);
                    return lerp(History, Filtered, ClipBlend);
                }

                float3 Frag(v2f i) : SV_Target
                {
                    // 带_Jitter抖动的当前帧图像
                    float2 uv = i.texcoord - _Jitter;
                    float4 Color = _MainTex.Sample(sampler_LinearClamp, uv);
                    if(_IgnoreHistory) return Color;
                    // 找遮挡最近像素点
                    float2 closest = GetClosestFragment(i.texcoord);
                    // 用运动向量回溯历史帧对应像素位置
                    float2 Motion = SAMPLE_TEXTURE2D(_CameraMotionVectorsTexture, sampler_LinearClamp, closest).xy;
                    float2 HistoryUV = i.texcoord - Motion;
                    float4 HistoryColor = _HistoryTex.Sample(sampler_LinearClamp, HistoryUV);
                    // 颜色裁剪，避免错误颜色
                    float3 AABBMin,AABBMax;
                    AABBMax = AABBMin = RGBToYCoCg(Color);
                    for(int k = 0; k < 9; k++){
                        float3 C = RGBToYCoCg(_MainTex.Sample(sampler_PointClamp, uv, kOffsets3x3[k]));
                        AABBMin = min(AABBMin, C);
                        AABBMax = max(AABBMax, C);
                    }
                    float3 HistoryYCoCg = RGBToYCoCg(HistoryColor);
                    HistoryColor.rgb = YCoCgToRGB(ClipHistory(HistoryYCoCg, AABBMin, AABBMax));
                    // 动态混合权重计算
                    float BlendFactor = saturate(0.05 + length(Motion) * 1000);
                    // 越界检查，防止历史 UV 无效
                    if(HistoryUV.x < 0 || HistoryUV.y < 0 || HistoryUV.x > 1.0f || HistoryUV.y > 1.0f)
                    {
                        BlendFactor = 1.0f;
                    }
                    // 混合输出：按融合比例在历史色和当前帧色之间插值
                    return lerp(HistoryColor, Color, BlendFactor);
                }

            ENDHLSL

        }
    }

}