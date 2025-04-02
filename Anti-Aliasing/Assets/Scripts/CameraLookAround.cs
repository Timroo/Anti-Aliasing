using UnityEngine;

public class CameraLookAround : MonoBehaviour
{
    public float rotationSpeed = 2.0f; // 鼠标控制旋转的灵敏度
    private Vector3 lastMousePosition;
    private float yaw = 0.0f;
    private float pitch = 0.0f;

    void Start()
    {
        // 初始化角度
        yaw = transform.eulerAngles.y;
        pitch = transform.eulerAngles.x;
    }

    void Update()
    {
        if (Input.GetMouseButtonDown(1)) // 右键按下时记录初始位置
        {
            lastMousePosition = Input.mousePosition;
        }

        if (Input.GetMouseButton(1)) // 右键按住时旋转
        {
            Vector3 delta = Input.mousePosition - lastMousePosition;
            lastMousePosition = Input.mousePosition;

            yaw += delta.x * rotationSpeed * Time.deltaTime;
            pitch -= delta.y * rotationSpeed * Time.deltaTime;
            pitch = Mathf.Clamp(pitch, -89f, 89f); // 限制上下旋转角度，避免翻转

            transform.rotation = Quaternion.Euler(pitch, yaw, 0f);
        }
    }
}
