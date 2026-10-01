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
#ifndef _WIN32
#include <errno.h>
#endif

#define PACKET_VERSION 3
#define SNAPSHOT_BYTES 472

static socket_t lan_socket = INVALID_SOCKET_VALUE;
static struct sockaddr_in lan_peer;
static int has_peer = 0;
static int is_host = 0;
static uint32_t reconnect_ip = 0;
static int reconnect_only = 0;
static int expected_coop = -1;

void ion_lan_close(void) {
    if (lan_socket != INVALID_SOCKET_VALUE) {
        CLOSE_SOCKET(lan_socket);
        lan_socket = INVALID_SOCKET_VALUE;
    }
    has_peer = 0;
    is_host = 0;
    reconnect_ip = 0;
    reconnect_only = 0;
    expected_coop = -1;
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
        !data || length < 1 || length > 1200) return 0;
    return (int)sendto(lan_socket, (const char *)data, length, 0,
                       (const struct sockaddr *)&lan_peer,
                       sizeof(lan_peer));
}

int ion_lan_recv(void *data, int capacity) {
    struct sockaddr_in sender;
    unsigned char packet[1201];
    int result, attempt;
    if (lan_socket == INVALID_SOCKET_VALUE || !data || capacity < 1) return 0;
    /* A rejected datagram must not stop the caller from draining valid traffic.
       Read the entire datagram so a truncated prefix cannot pass length checks. */
    for (attempt = 0; attempt < 24; ++attempt) {
#ifdef _WIN32
        int sender_length = sizeof(sender);
#else
        socklen_t sender_length = sizeof(sender);
#endif
        result = (int)recvfrom(lan_socket, (char *)packet, sizeof(packet), 0,
                              (struct sockaddr *)&sender, &sender_length);
        if (result < 0) {
#ifdef _WIN32
            if (WSAGetLastError() == WSAEMSGSIZE) continue;
#else
            if (errno == EINTR) continue;
#endif
            return 0;
        }
        if (result < 4 || result > capacity || result > 1200) continue;
        if (packet[0] != 'I' || packet[1] != 'L' ||
            packet[2] != PACKET_VERSION) continue;
        if (has_peer &&
            (sender.sin_addr.s_addr != lan_peer.sin_addr.s_addr ||
             sender.sin_port != lan_peer.sin_port)) continue;
        if (is_host) {
            if (packet[3] == 1 && result == 10) {
                if (packet[6] > 127 || packet[7] >= 5 ||
                    packet[8] >= 7 || packet[9] > 1) continue;
                if (reconnect_only && sender.sin_addr.s_addr != reconnect_ip) continue;
                if (expected_coop >= 0 && packet[9] != expected_coop) {
                    /* Report a wrong lobby mode without allowing it to claim
                       the host's only peer slot or reset an existing match. */
                    unsigned char reply[5] = {'I', 'L', PACKET_VERSION, 4, 0};
                    reply[4] = (unsigned char)expected_coop;
                    sendto(lan_socket, (const char *)reply, sizeof(reply), 0,
                           (const struct sockaddr *)&sender, sizeof(sender));
                    continue;
                }
                if (!has_peer) {
                    lan_peer = sender;
                    has_peer = 1;
                    reconnect_only = 0;
                }
            } else if (!(has_peer && packet[3] == 3 && result == 4)) continue;
        } else {
            if (!has_peer) continue;
            if (!((packet[3] == 2 && result == SNAPSHOT_BYTES) ||
                  (packet[3] == 3 && result == 4) ||
                  (packet[3] == 4 && result == 5 && packet[4] <= 1))) continue;
        }
        memcpy(data, packet, (size_t)result);
        return result;
    }
    return 0;
}

void ion_lan_set_mode(int cooperative) { expected_coop = cooperative != 0; }

int ion_lan_peer(void) { return has_peer; }

void ion_lan_release_peer(int keep_address) {
    if (is_host) {
        if (keep_address && has_peer) {
            reconnect_ip = lan_peer.sin_addr.s_addr;
            reconnect_only = 1;
        } else if (!keep_address) {
            reconnect_ip = 0;
            reconnect_only = 0;
        }
        has_peer = 0;
    }
}
