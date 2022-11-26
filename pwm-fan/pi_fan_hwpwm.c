/*
/
/ pi_fan_hwpwm.c, alwynallan@gmail.com 12/2020, no license
/ latest version: https://gist.github.com/alwynallan/1c13096c4cd675f38405702e89e0c536
/
/ Need    http://www.airspayce.com/mikem/bcm2835/index.html
/
/ Compile $ gcc -Wall pi_fan_hwpwm.c -lbcm2835 -o pi_fan_hwpwm
/
/ Disable $ sudo nano /boot/config.txt            [Raspbian, or use GUI]
/         $ sudo nano /boot/firmware/usercfg.txt  [Ubuntu]
/             # dtoverlay=gpio-fan,gpiopin=14,temp=80000 <- commented out, reboot
/             enable_uart=0                              <- needed? not Ubuntu
/             dtparam=audio=off                          <- needed? not Ubuntu
/             dtparam=i2c_arm=off                        <- needed? not Ubuntu
/             dtparam=spi=off                            <- needed? not Ubuntu
/
/ Run     $ sudo ./pi_fan_hwpwm -v
/
/ Forget  $ sudo ./pi_fan_hwpwm &
/         $ disown -a
/
/Output update by traisjames
*/

#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdarg.h>
#include <bcm2835.h>

#define PWM_PIN   0  // default, uses both GPIO 13 and GPIO 18
#define HIGH_TEMP 80.
#define ON_TEMP   65.
#define OFF_TEMP  60.
#define MIN_FAN   150
#define KICK_FAN  200
#define MAX_FAN   480

unsigned pin = PWM_PIN;
int verbose = 0;
int fan_state = 0;
double temp = 25.0;
pid_t global_pid;
int pwm_level = -555;

void usage()
{
   fprintf
   (stderr,
      "\n" \
      "Usage: sudo ./pi_fan_hwpwm [OPTION]...\n" \
      "\n" \
      "  -g <n> Use GPIO n for fan's PWM input, default 0 (both).\n" \
      "         Only hardware PWM capable GPIO 18 and GPIO 13 are present on\n" \
      "         the RasPi 4B pin header, and only GPIO 18 can be used with\n" \
      "         the unmodified case fan.\n" \
      "  -v     Verbose output\n" \
      "\n"
   );
}

void fatal(int show_usage, char *fmt, ...) {
   char buf[128];
   va_list ap;

   va_start(ap, fmt);
   vsnprintf(buf, sizeof(buf), fmt, ap);
   va_end(ap);
   fprintf(stderr, "%s\n", buf);
   if (show_usage) usage();
   fflush(stderr);
   exit(EXIT_FAILURE);
}

void run_write(const char *fname, const char *data) {
// https://opensource.com/article/19/4/interprocess-communication-linux-storage
  struct flock lock;
  lock.l_type = F_WRLCK;
  lock.l_whence = SEEK_SET;
  lock.l_start = 0;
  lock.l_len = 0;
  lock.l_pid = global_pid;
  int fd;
  if ((fd = open(fname, O_RDWR | O_CREAT, 0666)) < 0)
    fatal(0, "failed to open %s for writing", fname);
  if (fcntl(fd, F_SETLK, &lock) < 0)
    fatal(0, "fcntl failed to get lock on %s", fname);
  if (ftruncate(fd, 0) < 0)
    fatal(0, "truncate failed to on %s", fname);
  write(fd, data, strlen(data));
  close(fd);
}

void PWM_out(int level) {
  if(level > pwm_level && (level - pwm_level) < 5) return;
  if(level < pwm_level && (pwm_level - level) < 10) return;
  if(level != pwm_level) {
    if(pin == 0 || pin == 13) bcm2835_pwm_set_data(1, level);
    if(pin == 0 || pin == 18) bcm2835_pwm_set_data(0, level);
    pwm_level = level;
  }
}

void fan_loop(void) {
  if(!fan_state && (temp > ON_TEMP)) {
    PWM_out(KICK_FAN);
    fan_state = 1;
    return;
  }
  if(fan_state && (temp < OFF_TEMP)) {
    PWM_out(0);
    fan_state = 0;
    return;
  }
  if(fan_state) {
    unsigned out = (double) MIN_FAN + (temp - OFF_TEMP) / (HIGH_TEMP - OFF_TEMP) * (double)(MAX_FAN - MIN_FAN);
    if(out > MAX_FAN) out = MAX_FAN;
    PWM_out(out);
  }
}

int main(int argc, char *argv[]) {
  int opt;
  unsigned loop = 0;
  int t;
  FILE *ft;
  char buf[100];

  while ((opt = getopt(argc, argv, "g:v")) != -1) {
    switch (opt) {
    case 'g':
      pin = atoi(optarg);
      if(pin != 0 && pin != 13 && pin != 18) fatal(0, "Invalid GPIO");
      break;
    case 'v':
      verbose = 1;
      break;
    default:
      usage();
      exit(EXIT_FAILURE);
    }
  }
  if(optind != argc) fatal(1, "optind=%d argc=%d Unrecognized parameter %s", optind, argc, argv[optind]);

  global_pid = getpid();
  sprintf(buf, "%d\n", global_pid);
  run_write("/run/pi_fan_hwpwm.pid", buf);

  if(!bcm2835_init()) fatal(0, "bcm2835_init() failed");
  if(pin==0 || pin==13) bcm2835_gpio_fsel(13, BCM2835_GPIO_FSEL_ALT0);
  if(pin==0 || pin==18) bcm2835_gpio_fsel(18, BCM2835_GPIO_FSEL_ALT5);
  bcm2835_pwm_set_clock(2); // 19.2 / 2 MHz
  if(pin==0 || pin==13) bcm2835_pwm_set_mode(1, 1, 1);
  if(pin==0 || pin==13) bcm2835_pwm_set_range(1, 480);
  if(pin==0 || pin==18) bcm2835_pwm_set_mode(0, 1, 1);
  if(pin==0 || pin==18) bcm2835_pwm_set_range(0, 480);
  PWM_out(0);

  while(1) {
    loop++;
    ft = fopen("/sys/class/thermal/thermal_zone0/temp", "r");
    fscanf(ft, "%d", &t);
    fclose(ft);
    temp = 0.0001 * (double)t + 0.9 * temp;
    if((loop%4) == 0) { // every second
      fan_loop();
      sprintf(buf, "Time: %us, Temp: %.2fc, Fan Speed: %.1f%%\n", loop/4, temp, (float)pwm_level/(float)MAX_FAN*100.);
      run_write("/run/pi_fan_hwpwm.state", buf);
      if(verbose) fputs(buf, stdout);
    }
    usleep(250000);
  }

  exit(EXIT_SUCCESS);
}
