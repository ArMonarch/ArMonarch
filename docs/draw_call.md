# Structure of procedures call order
1. UseProgram
2. Get attribute/uniform locations
3. Set uniforms
4. Create + Bind VAO
5. Create + Bind VBO → BufferData
6. Create + Bind EBO → BufferData (if using indexed drawing)
7. EnableVertexAttribArray + VertexAttribPointer
8. DrawElements / DrawArrays
