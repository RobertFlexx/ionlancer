/* Small nonblocking UDP bridge for the Modula-2 arena. A host accepts one
   peer at a time, and both platforms use the same packet protocol. */
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET socket_t;
#define INVALID_SOCKET_VALUE INVALID_SOCKET
#define CLOSE_SOCKET closesocket
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int socket_t;
#define INVALID_SOCKET_VALUE (-1)
#define CLOSE_SOCKET close
#endif

#include <stdint.h>
#include <string.h>

static socket_t lan_socket = INVALID_SOCKET_VALUE;
static struct sockaddr_in lan_peer;
static int has_peer = 0;
static int is_host = 0;

void ion_lan_close(void) {
    if (lan_socket != INVALID_SOCKET_VALUE) {
        CLOSE_SOCKET(lan_socket);
        lan_socket = INVALID_SOCKET_VALUE;
    }
    has_peer = 0;
    is_host = 0;
#ifdef _WIN32
    WSACleanup();
#endif
}

int ion_lan_open(int host, int a, int b, int c, int d, int port) {
    struct sockaddr_in address;
    uint32_t ipv4;
#ifdef _WIN32
    WSADATA wsa;
    u_long nonblocking = 1;
#endif
    ion_lan_close();
    if (port < 1 || port > 65535) return 0;
    if (a < 0 || a > 255 || b < 0 || b > 255 ||
        c < 0 || c > 255 || d < 0 || d > 255) return 0;
#ifdef _WIN32
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 0;
#endif
    lan_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (lan_socket == INVALID_SOCKET_VALUE) {
        ion_lan_close();
        return 0;
    }
#ifdef _WIN32
    if (ioctlsocket(lan_socket, FIONBIO, &nonblocking) != 0) {
#else
    if (fcntl(lan_socket, F_SETFL, O_NONBLOCK) != 0) {
#endif
        ion_lan_close();
        return 0;
    }
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)(host ? port : 0));
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(lan_socket, (struct sockaddr *)&address, sizeof(address)) != 0) {
        ion_lan_close();
        return 0;
    }
    is_host = host != 0;
    if (!is_host) {
        ipv4 = ((uint32_t)a << 24) | ((uint32_t)b << 16) |
               ((uint32_t)c << 8) | (uint32_t)d;
        memset(&lan_peer, 0, sizeof(lan_peer));
        lan_peer.sin_family = AF_INET;
        lan_peer.sin_port = htons((uint16_t)port);
        lan_peer.sin_addr.s_addr = htonl(ipv4);
        has_peer = 1;
    }
    return 1;
}

int ion_lan_send(const void *data, int length) {
    if (lan_socket == INVALID_SOCKET_VALUE || !has_peer ||
        length < 1 || length > 1200) return 0;
    return (int)sendto(lan_socket, (const char *)data, length, 0,
                       (const struct sockaddr *)&lan_peer,
                       sizeof(lan_peer));
}

int ion_lan_recv(void *data, int capacity) {
    struct sockaddr_in sender;
#ifdef _WIN32
    int sender_length = sizeof(sender);
#else
    socklen_t sender_length = sizeof(sender);
#endif
    int result;
    if (lan_socket == INVALID_SOCKET_VALUE || capacity < 1) return 0;
    result = (int)recvfrom(lan_socket, (char *)data, capacity, 0,
                           (struct sockaddr *)&sender, &sender_length);
    if (result <= 0) return 0;
    if (has_peer) {
        if (sender.sin_addr.s_addr != lan_peer.sin_addr.s_addr ||
            sender.sin_port != lan_peer.sin_port) return 0;
    } else if (is_host && result >= 4) {
        const unsigned char *bytes = (const unsigned char *)data;
        if (bytes[0] != 'I' || bytes[1] != 'L' ||
            bytes[2] != 1 || bytes[3] != 1) return 0;
        lan_peer = sender;
        has_peer = 1;
    } else return 0;
    return result;
}

int ion_lan_peer(void) { return has_peer; }

void ion_lan_release_peer(void) {
    if (is_host) has_peer = 0;
}
