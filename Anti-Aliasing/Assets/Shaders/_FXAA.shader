Shader "_FXAA"{
    Properties{
        _MainTex("Texture", 2D) = "white" {}
    }

    CGINCLUDE
        #include "UnityCG.cginc"
        sampler2D _MainTex;
        float4 _MainTex_TexelSize;

        float _ContrastThreshold, _RelativeThreshold;

        struct a2v{
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
        };

        struct v2f{
            float4 pos : SV_POSITION;
            float2 uv : TEXCOORD0;
        };
        
        v2f Vert(a2v v){
            v2f o;
            o.pos = UnityObjectToClipPos(v.vertex);
            o.uv = v.uv;
            return o;
        }

        float4 Farg_FXAAQUality(v2f i): SV_Target{
            float2 uv = i.uv;
            float2 texelSize = _MainTex_TexelSize.xy;
            float4 origin = tex2D(_MainTex, uv);

            //【边缘检测】
            // - 用亮度判断边缘
            // - Luminance() : dot(rgb, float3(0.299, 0.587, 0.114))
            float M = Luminance(origin);
            float E = Luminance(tex2D(_MainTex, uv + float2( 1 ,  0) * texelSize));
            float N  = Luminance(tex2D(_MainTex, uv + float2( 0 ,  1) * texelSize));
			float W  = Luminance(tex2D(_MainTex, uv + float2(-1 ,  0) * texelSize));
			float S  = Luminance(tex2D(_MainTex, uv + float2( 0 , -1) * texelSize));
			float NW = Luminance(tex2D(_MainTex, uv + float2(-1 ,  1) * texelSize));
			float NE = Luminance(tex2D(_MainTex, uv + float2( 1 ,  1) * texelSize));
			float SW = Luminance(tex2D(_MainTex, uv + float2(-1 , -1) * texelSize));
			float SE = Luminance(tex2D(_MainTex, uv + float2( 1 , -1) * texelSize));

            // 计算对比度
            float maxLuma = max(max(max(N,E),max(W,S)),M);
            float minLuma = min(min(min(N,E),min(W,S)),M);
            float contrast = maxLuma - minLuma;

            // 对比度判断，决定是否需要抗锯齿
            if(contrast < max(_ContrastThreshold, maxLuma * _RelativeThreshold))
                return origin;
            
            // 【基于亮度的混合因子】
            // - 用邻域平均亮度构建一个参考亮度
            // - 取当前像素与邻域平均值的偏差
            // - 除以整体对比度归一化，得到一个 saturate(0~1) 范围的混合因子
            // - 用 smoothstep 让边缘过渡更柔和，再平方加重效果（更平滑）
            float Filter = 2 * (N+E+S+W) + NE + NW + SE + SW;
            Filter = Filter / 12 ;
            Filter = abs(Filter - M);
            Filter = saturate(Filter / contrast);
            float pixelBlend = smoothstep(0, 1, Filter);
            pixelBlend = pixelBlend * pixelBlend;

            // 【锯齿方向】
            float vertical = abs(N + S - 2 * M) * 2 + abs(NE + SE - 2 * E) + abs(NW + SW - 2 * W);
            float horizontal = abs(E + W - 2 * M) * 2 + abs(NE + NW - 2 * N) + abs(SE + SW - 2 * S); 
            bool isHorizontal = vertical > horizontal;

            // 【混合方向】
            //  - 水平锯齿，上下模糊
            //  - 垂直锯齿，左右模糊
            float2 pixelStep = isHorizontal ? float2(0, texelSize.y) : float2(texelSize.x, 0);
            // 锯齿方向亮度差对比，确定混合方向的正负
            // - 北、东为正
            // - 南、西为负
            float positive = abs((isHorizontal ? N : E) - M);
            float negative = abs((isHorizontal ? S : W) - M);
            float gradient, oppositeLuminance;
            if(positive > negative){
                gradient = positive;
                oppositeLuminance = isHorizontal ? N : E;
            }else{
                // 亮度差大的一侧在“下/右”，则 PixelStep 翻转方向
                pixelStep = - pixelStep;
                gradient = negative;
                oppositeLuminance = isHorizontal ? S : W;
            }

            // 【边界的混合因子】
            // - 从当前像素沿边缘方向偏移半步，进入锯齿边界中间位置
            // - 沿锯齿边界方向（即边缘延申方向）进行多次采样
            float2 uvEdge = uv;
            uvEdge += pixelStep * 0.5f;
            float2 edgeStep = isHorizontal ? float2(texelSize.x, 0) : float2(0, texelSize.y);

            // 这里是定义搜索的步长，步长越长，效果越好
            #define _SearchSteps 15
            // 未搜索到边界时，猜测的边界距离
            #define _Guess 8

            // 沿着锯齿边界两侧，进行搜索，找到锯齿边界
            // edgeLuminance：锯齿边界颜色，设置为两个颜色的中间值
            // gradientThreshold：阈值，亮度超过这个值就说明到边界了
            float edgeLuminance = (M + oppositeLuminance) * 0.5f;
            float gradientThreshold = gradient * 0.25f;
            float pLuminanceDelta, nLuminanceDelta, pDistance, nDistance;
            int x;
            UNITY_UNROLL
            // 正向搜索
            for(x = 1; x <= _SearchSteps; ++x){
                pLuminanceDelta = Luminance(tex2D(_MainTex, uvEdge + x * edgeStep)) - edgeLuminance;
                if(abs(pLuminanceDelta) > gradientThreshold){
                    pDistance = x * (isHorizontal ? edgeStep.x : edgeStep.y);
                    break;
                }
            }
            // - 没找到，则猜测边界距离
            if (x == _SearchSteps + 1){
                pDistance = edgeStep * _Guess;
            }

            // 反向搜索
            UNITY_UNROLL
            for(x = 1; x <= _SearchSteps; ++x){
                nLuminanceDelta = Luminance(tex2D(_MainTex, uvEdge - x * edgeStep)) - edgeLuminance;
                if(abs(nLuminanceDelta) > gradientThreshold){
                    nDistance = x * (isHorizontal ? edgeStep.x : edgeStep.y);
                    break;
                }
            }
            // - 没找到，则猜测边界距离
            if(x == _SearchSteps + 1) {
			    nDistance = edgeStep * _Guess;
			}

            // 计算基于边界的混合系数 
            // - 判断边界方向是否合理，计算edgeBlend
            float edgeBlend = 0;
            if (pDistance < nDistance){
                if(sign(pLuminanceDelta) == sign(M - edgeLuminance)){
                    edgeBlend = 0;
                }else{
                    edgeBlend = 0.5f - pDistance / (pDistance + nDistance);
                }
            }else{
                if(sign(nLuminanceDelta) == sign(M - edgeLuminance)){
                    edgeBlend = 0;
                }else{
                    edgeBlend = 0.5f - nDistance / (pDistance + nDistance);
                }
            }

            // 取最大混合因子
            float finalBlend = max(pixelBlend, edgeBlend);
            // float4 result = tex2D(_MainTex, uv + pixelStep * finalBlend);
            // 线性插值采样
            float4 result = tex2D(_MainTex, uv + pixelStep * finalBlend);
            return result;
        }
        
        float4 Frag_FXAAConsole(v2f i) : SV_Target{
            float2 uv = i.uv;
            float2 texelSize = _MainTex_TexelSize.xy;
            float4 origin = tex2D(_MainTex, uv);
            float M = Luminance(origin);
            float NW = Luminance(tex2D(_MainTex, uv + float2(-1, 1) * texelSize * 0.5));
            float NE = Luminance(tex2D(_MainTex, uv + float2( 1, 1) * texelSize * 0.5));
            float SW = Luminance(tex2D(_MainTex, uv + float2(-1,-1) * texelSize * 0.5));
            float SE = Luminance(tex2D(_MainTex, uv + float2( 1,-1) * texelSize * 0.5));
            // 计算对比度
            float maxLuma = max(max(NW, NE), max(SW, SE));
			float minLuma = min(min(NW, NE), min(NW, NE));
			float contrast = max(maxLuma, M) -  min(minLuma, M);

            // 判断是否抗锯齿
            if(contrast < max(_ContrastThreshold, maxLuma * _ContrastThreshold))
                return origin;
            
            // 修正NE亮度，防止垂直方向误判
            // NVIDIA FXAA 的经典做法
            NE += 1.0f / 384.0f;
            
            // sobel-like 梯度方向（亮度跳变方向）
            float2 gradient;
            gradient.x = (NE + SE) - (NW + SW); // X方向亮度变化
            gradient.y = (SW + SE) - (NW + NE); // Y方向亮度变化

            // 旋转90度 得到“锯齿延申方向”
            float2 dir = float2(-gradient.y, gradient.x);
            dir = normalize(dir);

            // 根据亮度差判断锯齿边缘方向
            // float2 dir;
            // dir.x = -((NW + NE) - (SW + SE));
            // dir.y = ((NE + SE) - (NW + SW));
            // dir = normalize(dir);

            // 沿方向模糊采样一次
            // - 沿锯齿方向两侧分别采样，再平均得到第一次模糊结果。
            #define _Scale 0.5
            float2 dir1 = dir * _MainTex_TexelSize.xy * _Scale;
            float4 N1 = tex2D(_MainTex, uv - dir1);
            float4 P1 = tex2D(_MainTex, uv + dir1);
            float4 result = (N1 + P1) * 0.5;
     
            // 再次锐化模糊采样（提高质量）
            #define _Sharpness 8
            float dirAbsMinTimesC = min(abs(dir1.x), abs(dir1.y)) * _Sharpness;
            float2 dir2 = clamp(dir1.xy / dirAbsMinTimesC, -2.0, 2.0) * 2;
            float4 N2 = tex2D(_MainTex, uv - dir2 * _MainTex_TexelSize.xy);
            float4 P2 = tex2D(_MainTex, uv + dir2 * _MainTex_TexelSize.xy);
            float4 result2 = (N2 + P2) * 0.25f + result * 0.5f;
            // 判断是否使用增强后的结果
            float newLum = Luminance(result2);
            if((newLum >= minLuma) && (newLum <= maxLuma)){
                result = result2;
            }
			return result;
		}

    ENDCG

    SubShader{
        Cull Off ZTest Always ZWrite Off

        Pass{
            CGPROGRAM
            #pragma vertex Vert
            #pragma fragment Farg_FXAAQUality
            ENDCG
        }

        Pass{
            CGPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag_FXAAConsole
            ENDCG
        }
    }

}