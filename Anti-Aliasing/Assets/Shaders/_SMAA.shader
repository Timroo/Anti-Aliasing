Shader "_SMAA"{
    Properties{
        _MainTex("Texture", 2D) = "white" {}
    }
    HLSLINCLUDE
        #pragma exclude_renderers gles
        #include "StdLib.hlsl"
        #include "Colors.hlsl"

        Texture2D _MainTex;
        Texture2D _BlendTex;
        float4 _MainTex_TexelSize;

        SamplerState sampler_LinearClamp;
        SamplerState sampler_PointClamp;

        struct a2v{
            float3 vertex : POSITION;
            float2 texcoord : TEXCOORD0;
        };

        struct v2f{
            float4 vertex : SV_POSITION;
            float2 texcoord : TEXCOORD0;
        };

        v2f Vert(a2v v){
            v2f o;
            o.vertex = mul(unity_MatrixVP, mul(unity_ObjectToWorld, float4(v.vertex, 1)));
            o.texcoord = v.texcoord;
            return o;
        }

    ENDHLSL

    SubShader{
        Cull Off ZWrite Off ZTest Always

        // Pass 01:边缘检测
        Pass{
            HLSLPROGRAM
                float4 Frag_Edge(v2f i) : SV_Target{
                    #define THRESHOLD 0.05f;
                    float2 uv = i.texcoord;
                    float2 size = _MainTex_TexelSize.xy;
                    float lumCenter = Luminance(_MainTex.Sample(sampler_LinearClamp, uv));

                    float lumDiffLeft    = abs(Luminance(_MainTex.Sample(sampler_LinearClamp, uv + float2(-size.x, 0))) - lumCenter);
                    float lumDiffLeft2   = abs(Luminance(_MainTex.Sample(sampler_LinearClamp, uv + float2(-size.x * 2, 0))) - lumCenter);
                    float lumDiffRight   = abs(Luminance(_MainTex.Sample(sampler_LinearClamp, uv + float2(size.x, 0))) - lumCenter);
                    float lumDiffTop     = abs(Luminance(_MainTex.Sample(sampler_LinearClamp, uv + float2(0, -size.y))) - lumCenter);
                    float lumDiffTop2    = abs(Luminance(_MainTex.Sample(sampler_LinearClamp, uv + float2(0, -size.y * 2))) - lumCenter);
                    float lumDiffBottom  = abs(Luminance(_MainTex.Sample(sampler_LinearClamp, uv + float2(0, size.y))) - lumCenter);

                    float lumMax = max(max(lumDiffLeft, lumDiffRight), max(lumDiffTop, lumDiffBottom));

                    // 只判断上界和左界
                    // - 避免边缘重复绘制;保持一致性;节约性能

                    // 判断左侧边界
                    // 双重判定机制
                    // - 明显边缘
                    // - 渐变过渡
                    bool edgeLeft = lumDiffLeft > THRESHOLD;
                    edgeLeft = edgeLeft && lumDiffLeft  > (max(lumMax, lumDiffLeft2) * 0.5f);

                    // 判断上测边界
                    bool edgeTop = lumDiffTop > THRESHOLD;
                    edgeTop = edgeTop && lumDiffTop > (max(lumMax, lumDiffTop2) * 0.5f);

                    return float4(edgeLeft ? 1 : 0, edgeTop ? 1 : 0, 0, 0);
                }
                #pragma vertex Vert
                #pragma fragment Frag_Edge
            ENDHLSL
        }

        // Pass 02: 边缘混合权重计算
        Pass{
            HLSLPROGRAM
                // 圆角系数，保留物体实际边缘：0 全部保留；1 不保留
                #define ROUNDING_FACTOR 0.25
                // 最大搜索步长
                #define MAXSTEPS 10

                #pragma vertex Vert
                #pragma fragment Frag_Blend

            //【边界搜索】
                // 沿着左侧进行边界搜索
                float SearchXLeft(float2 coord){
                    coord -= float2(1.5f, 0);
                    float edge = 0;    // edge
                    int i = 0;
                    UNITY_UNROLL
                    for(; i < MAXSTEPS; i++){
                        // 水平锯齿体现在上边界
                        edge = _MainTex.Sample(sampler_LinearClamp, coord * _MainTex_TexelSize.xy).g;
                        // 采样值小于0.9，说明从 边缘 走到了 不是边缘 的地方，停止搜索
                        [flatten]
                        if (edge < 0.9f) break;
                        // 大步长，加速收敛搜索
                        coord -= float2(2, 0);
                    }
                    // i是步数，e是当前采样值，*2 是每次走了2像素
                    // max 是做安全限制
                    return min(2.0 * (i + edge), 2.0 * MAXSTEPS);
                }
                // 沿着右边界搜索
                float SearchXRight(float2 coord){
                    coord += float2(1.5f, 0);
                    float edge = 0;
                    int i = 0;
                    UNITY_UNROLL
                    for(; i < MAXSTEPS; i++){
                        edge = _MainTex.Sample(sampler_LinearClamp, coord * _MainTex_TexelSize.xy).g;
                        [flatten]
                        if (edge < 0.9f) break;
                        coord += float2(2, 0);
                    }
                    return min(2.0 * (i + edge), 2.0 * MAXSTEPS);
                }
                // 沿上边界搜索
                float SearchYUp(float2 coord){
                    coord -= float2(0, 1.5f);
                    float edge = 0;
                    int i = 0;
                    UNITY_UNROLL
                    for(; i < MAXSTEPS; i++){
                        edge = _MainTex.Sample(sampler_LinearClamp, coord * _MainTex_TexelSize.xy).r;
                        [flatten]
                        if (edge < 0.9f) break;
                        coord -= float2(0, 2);  //向上为负
                    }
                    return min(2.0 * (i + edge), 2.0 * MAXSTEPS);
                }
                // 沿下边界搜索
                float SearchYDown(float2 coord){
                    coord += float2(0, 1.5f);
                    float edge = 0;
                    int i = 0;
                    UNITY_UNROLL
                    for(; i < MAXSTEPS; i++){
                        edge = _MainTex.Sample(sampler_LinearClamp, coord * _MainTex_TexelSize.xy).r;
                        [flatten]
                        if (edge < 0.9f) break;
                        coord += float2(0, 2);
                    }
                    return min(2.0 * (i + edge), 2.0 * MAXSTEPS);
                }
            
            //【判断边界类型】
                // 启发式的结构模式判断：
                // - 因为颜色在图像中通常是连续/渐变的，
                // - 如果某个方向的颜色值还比较高，说明那里可能仍处在边缘区域或与其它边缘相连。
                //根据双线性采样得到的值，来判断边界的模式
                // y：边缘结构存在
                // z：结构链接/分叉
                bool4 ModeOfSingle(float value){
                    bool4 ret = false;
                    if(value > 0.875)
                        ret.yz = bool2(true, true);
                    else if(value > 0.5)
                        ret.z = true;
                    else if(value > 0.125)
                        ret.y = true;
                    return ret;
                }
                // 判断两侧的模式
                bool4 ModeOfDouble(float value1, float value2){
                    bool4 ret;
                    // xy：左/上测的情况
                    // zw：右/下测的情况
                    ret.xy = ModeOfSingle(value1).yz;
                    ret.zw = ModeOfSingle(value2).yz;
                    return ret;
                }

                //  单侧L型, 另一侧没有
                //  |____
                // 返回：基于“L 型边缘结构”的混合权重面积值。
                float L_N_Shape(float d, float m){
                    // d：左右两边混合总宽度（从左边缘到右边缘）
                    // m：当前像素中心到边缘的距离（像素单位）
                    float l = d * 0.5;
                    float s = 0;
                    [flatten]
                    if(l > (m + 0.5)){ // 当前像素离边缘较远，在混合区域内部
                        s = (l - m) * 0.5 / l;
                    }
                    else if (l > (m - 0.5)){ // 当前像素靠近边缘线，混合区域呈三角形
                        float a = l - m + 0.5;
                        float s = a * a * 0.25 * rcp(l);
                    }
                    // 没进循环：完全不在混合区域
                    return s;
                }

                //  双侧L型, 且方向相同
                //  |____|
                // 
                float L_L_S_Shape(float d1, float d2)
                {
                    float d = d1 + d2;
                    float s1 = L_N_Shape(d, d1);
                    float s2 = L_N_Shape(d, d2);
                    return s1 + s2;
                }

                //  双侧L型/或一侧L, 一侧T, 且方向不同, 这里假设左侧向上, 来取正负
                //  |____    |___|    
                //       |       |
                float L_L_D_Shape(float d1, float d2)
                {
                    float d = d1 + d2;
                    float s1 = L_N_Shape(d, d1);
                    float s2 = -L_N_Shape(d, d2);
                    return s1 + s2;
                }

                //输入：锯齿左右边界长度float2(left, right)；左边尽头结构形态标记 l；右边尽头结构形态标记r
                float Area(float2 d, bool4 left, bool4 right){
                    // result为正, 表示将该像素点颜色扩散至上/左侧;
                    // result为负, 表示将上/左侧颜色扩散至该像素
                    float result = 0;
                    [branch]

                    if(!left.y && !left.z){
                        [branch]
                        if(right.y && !right.z){
                            result = L_N_Shape(d.y + d.x + 1, d.y + 0.5);
                        }
                        else if(!right.y && right.z){
                            result = -L_N_Shape(d.y + d.x + 1, d.y + 0.5);
                        }
                    }
                    else if(left.y && !left.z){
                        [branch]
                        if(right.z){
                            result = L_L_D_Shape(d.x + 0.5, d.y + 0.5);
                        }
                        else if(!right.y){
                            result = L_N_Shape(d.y + d.x + 1, d.x + 0.5);
                        }
                        else{
                            result = L_L_S_Shape(d.x + 0.5, d.y + 0.5);
                        }
                    }
                    else if(!left.y && left.z){
                        [branch]
                        if(right.y){
                            result = -L_L_D_Shape(d.x + 0.5, d.y + 0.5);
                        }
                        else if(!right.z){
                            result = -L_N_Shape(d.y + d.x + 1, d.y + 0.5);
                        }
                        else{
                            result = -L_L_S_Shape(d.x + 0.5, d.y + 0.5);
                        }
                    }
                    else{
                        [branch]
                        if(right.y && !right.z){
                            result = -L_L_D_Shape(d.x + 0.5, d.y + 0.5);
                        }
                        else if(!right.y && right.z){
                            result = L_L_D_Shape(d.x + 0.5, d.y + 0.5);
                        }
                    }
                
                    #ifdef ROUNDING_FACTOR
                        bool apply = false;
                        if(result > 0){
                            if(d.x < d.y && left.x){
                                apply = true;
                            }
                            else if(d.x >= d.y && right.x)
                            {
                                apply = true;
                            }
                        }
                        else if (result < 0)
                        {
                            if(d.x < d.y && left.w)
                            {
                                apply = true;
                            }
                            else if(d.x >= d.y && right.w)
                            {
                                apply = true;
                            }
                        }
                        if (apply)
                        {
                            result = result * ROUNDING_FACTOR;
                        }
                    #endif
                    return result;
                }


                float4 Frag_Blend(v2f i) : SV_Target{
                    float2 uv = i.texcoord;
                    float2 screenPos = i.texcoord * _MainTex_TexelSize.zw;
                    float2 edge = _MainTex.Sample(sampler_LinearClamp, uv).xy;
                    float4 result = 0;
                    bool4 l,r;
                    
                    // 说明上边是横向边缘，需要做横向混合
                    // - g通道但凡有颜色了，就是上边缘
                    if(edge.g > 0.1f){
                        float left = SearchXLeft(screenPos);
                        float right = SearchXRight(screenPos);
                        // 如果采用圆角模式：采2个点，判断边缘形态
                        #ifdef ROUNDING_FACTOR
                            // 在左侧边界位置的上方和下方各取一个样本，用于判断边缘形状
                            // - 下为正；上为负
                            // - “偏心偏移”是为了 改善梯形识别与边角插值
                            float left1 = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(-left, -1.25)) * _MainTex_TexelSize.xy, 0).r;
                            float left2 = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(-left, 0.75)) * _MainTex_TexelSize.xy, 0).r;
                            l = ModeOfDouble(left1, left2);
                            float right1 = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(right + 1, -1.25)) * _MainTex_TexelSize.xy, 0).r;
                            float right2 = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(right + 1, 0.75)) * _MainTex_TexelSize.xy, 0).r;
                            r = ModeOfDouble(right1, right2);
                        // 如果不采用圆角模式：只采1个点，判断边缘
                        #else
                            float left_value = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(-left, -0.25)) * _MainTex_TexelSize.xy, 0).r;
                            float right_value = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(right + 1, -0.25)) * _MainTex_TexelSize.xy, 0).r;
                            l = ModeOfSingle(left_value);
                            r = ModeOfSingle(right_value);
                        #endif
                            float value = Area(float2(left, right), l, r);
                            result.xy = float2(-value, value);
                    }
                    // 说明有左边界，要做纵向混合
                    if (edge.r > 0.1f){
                        float up = SearchYUp(screenPos);
                        float down = SearchYDown(screenPos);

                        bool4 u, d;
                        #ifdef ROUNDING_FACTOR
                            float up1 = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(-1.25, -up)) * _MainTex_TexelSize.xy, 0).g;
                            float up2 = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(0.75, -up)) * _MainTex_TexelSize.xy, 0).g;
                            float down1 = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(-1.25, down + 1)) * _MainTex_TexelSize.xy, 0).g;
                            float down2 = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(0.75, down + 1)) * _MainTex_TexelSize.xy, 0).g;
                            u = ModeOfDouble(up1, up2);
                            d = ModeOfDouble(down1, down2);
                        #else
                            float up_value = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(-0.25, -up)) * _MainTex_TexelSize.xy, 0).g;
                            float down_value = _MainTex.SampleLevel(sampler_LinearClamp, (screenPos + float2(-0.25, down + 1)) * _MainTex_TexelSize.xy, 0).g;
                            u = ModeOfSingle(up_value);
                            d = ModeOfSingle(down_value);
                        #endif
                            float value = Area(float2(up, down), u, d);
                            result.zw = float2(-value, value);
                    }
                    return result;
                    // result = float4(offsetLeft, offsetRight, offsetUp, offsetDown);
                    // (-left, right, -up, down)
                }
            ENDHLSL
        }

        // Pass03 混合
        Pass{
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            float4 Frag(v2f i): SV_TARGET{
                float2 uv = i.texcoord;
                // 将 UV 转换为整数像素坐标，用于 .Load() 精准对齐像素采样。
                // _MainTex_TexelSize(x = 1/width, y = 1/height, z = width, w = height)
                int2 pixelCoord = uv * _MainTex_TexelSize.zw;
                // 当前像素的权重
                float4 current = _BlendTex.Load(int3(pixelCoord , 0));
                // 右边和下面像素的权重
                float R = _BlendTex.Load(int3(pixelCoord + int2(1, 0), 0)).a;
                float B = _BlendTex.Load(int3(pixelCoord + int2(0, 1), 0)).g;

                float4 a = float4(current.r, B, current.b, R);
                float4 w = a * a * a;
                float sum = dot(w, 1.0);//权重总和

                [branch]
                if(sum > 0){
                    //RG通道，锯齿方向是左右的，沿着上下混合，因此要乘以屏幕空间高度的倒数
                    //BA通道，锯齿方向是上下的，沿着左右混合，因此要乘以屏幕空间宽度的倒数
                    float4 o = a * _MainTex_TexelSize.yyxx;
                    float4 color = 0;
                    // mad(a,b,c) = a * b + c
                    color = mad(_MainTex.SampleLevel(sampler_LinearClamp, uv + float2( 0.0,-o.r), 0), w.r, color);// 上
                    color = mad(_MainTex.SampleLevel(sampler_LinearClamp, uv + float2( 0.0, o.g), 0), w.g, color);// 下
                    color = mad(_MainTex.SampleLevel(sampler_LinearClamp, uv + float2(-o.b, 0.0), 0), w.b, color);// 左
                    color = mad(_MainTex.SampleLevel(sampler_LinearClamp, uv + float2( o.a, 0.0), 0), w.a, color);// 右
                    return color/sum;
                } 
                else{
                    return _MainTex.SampleLevel(sampler_LinearClamp, uv, 0);
                }
            }

            ENDHLSL
        }
    }

}
