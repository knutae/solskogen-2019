//#define USE_START 1
#if defined(DEBUG)
#define API_CHECK 1
#endif

#include <GLES3/gl32.h>
#include <gtk/gtk.h>
#ifndef DEBUG
#include "gen/shaders.h"
#endif

#define EMPTY_SHADER "void main(){}"

#define GEOMETRY_SHADER \
  "#version 450\n" \
  "layout(points)in;" \
  "layout(triangle_strip,max_vertices=4)out;" \
  "out vec2 C;" \
  "void E(float u,float v){C=vec2(u+1,v+1);gl_Position=vec4(u,v,0,1);EmitVertex();}" \
  "void main(){E(-1,-1);E(1,-1);E(-1,1);E(1,1);}"

#ifndef DEBUG
// Redefine GTK casting macros as direct casts
#undef GTK_GL_AREA
#undef GTK_CONTAINER
#undef GTK_WINDOW
#undef GTK_WIDGET
#define GTK_GL_AREA (GtkGLArea*)
#define GTK_CONTAINER (GtkContainer*)
#define GTK_WINDOW (GtkWindow*)
#define GTK_WIDGET (GtkWidget*)
#endif

GLuint create_shader(const char *source, GLenum type) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, NULL);
  glCompileShader(shader);
#ifdef API_CHECK
  GLint success = 0;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
  if (!success) {
    char logBuffer[4096];
    GLsizei length;
    glGetShaderInfoLog(shader, sizeof(logBuffer), &length, logBuffer);
    printf("Shader compilation failed.\n%s\n", logBuffer);
    exit(1);
  }
#endif
  return shader;
}

GLuint vba;
GLuint program;

gboolean render(GtkGLArea *area, GdkGLContext *context) {
  GtkAllocation size;
  gtk_widget_get_allocation(GTK_WIDGET(area), &size);
  glUseProgram(program);
  glBindVertexArray(vba);
  glUniform1f(0, size.width);
  glUniform1f(1, size.height);
  glDrawArrays(GL_POINTS, 0, 1);
  return TRUE;
}

#ifdef DEBUG
GLuint load_shader(const char * filename, GLenum type) {
  FILE * f = fopen(filename, "r");
  if (!f) {
    printf("Failed to open %s\n", filename);
    exit(1);
  }
  fseek(f, 0, SEEK_END);
  long length = ftell(f);
  fseek(f, 0, SEEK_SET);
  char buffer[length + 1];
  fread(buffer, 1, length, f);
  buffer[length] = '\0';
  fclose(f);
  return create_shader(buffer, type);
}
#endif

void realize(GtkGLArea *area) {
  gtk_gl_area_make_current(area);
#ifdef API_CHECK
  if (gtk_gl_area_get_error (area) != NULL) {
    printf("gtk_gl_area_get_error");
    exit(1);
  }
#endif

  program = glCreateProgram();
  GLuint vertex_shader = create_shader(EMPTY_SHADER, GL_VERTEX_SHADER);
  GLuint geometry_shader = create_shader(GEOMETRY_SHADER, GL_GEOMETRY_SHADER);
#ifdef DEBUG
  system("mkdir -p gen && unifdef -b -x2 -DDEBUG -o gen/fshader-debug.glsl fshader.glsl");
  GLuint fragment_shader = load_shader("gen/fshader-debug.glsl", GL_FRAGMENT_SHADER);
#else
  GLuint fragment_shader = create_shader(fshader_glsl, GL_FRAGMENT_SHADER);
#endif
  glAttachShader(program, vertex_shader);
  glAttachShader(program, geometry_shader);
  glAttachShader(program, fragment_shader);
  glLinkProgram(program);

#ifdef API_CHECK
  GLint success = 0;
  glGetProgramiv(program, GL_LINK_STATUS, &success);
  if (!success) {
    char logBuffer[4096];
    GLsizei length;
    glGetShaderInfoLog(program, sizeof(logBuffer), &length, logBuffer);
    printf("Shader compilation failed.\n%s\n", logBuffer);
    exit(1);
  }
#endif

  glGenVertexArrays(1, &vba);
}

void key_press(GtkWidget * widget, GdkEventKey * event) {
  if (event->keyval == GDK_KEY_Escape) {
#if defined(DEBUG)
    gtk_main_quit();
#else
    // sys_exit_group (exit all threads) syscall
    asm("mov $231,%rax; mov $0,%rdi; syscall");
#endif
  }
}

#ifdef USE_START
void _start()
#else
int main()
#endif
{
  gtk_init(NULL, NULL);
  GtkWidget * window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget * area = gtk_gl_area_new();
  gtk_gl_area_set_auto_render(GTK_GL_AREA(area), FALSE);

  gtk_container_add(GTK_CONTAINER(window), area);
  gtk_window_fullscreen(GTK_WINDOW(window));

  g_signal_connect (area, "realize", G_CALLBACK (realize), NULL);
  g_signal_connect (area, "render", G_CALLBACK (render), NULL);
  g_signal_connect (window, "key-press-event", G_CALLBACK(key_press), NULL);

  gtk_widget_show_all(window);

  gtk_main();
#ifdef USE_START
  // exit syscall (x86_64 asm)
  asm("mov $60,%rax; mov $0,%rdi; syscall");
#else
  return 0;
#endif
}

#ifndef DEBUG
// Minimal implementations of crt1.o libc functions.
// With these defined, we don't need to link libc. Probably.
void __libc_csu_init() {}
void __libc_csu_fini() {}
void __libc_start_main() { main(); }
#endif
