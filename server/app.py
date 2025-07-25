from flask import Flask, request
import binascii
import math
import seal

app = Flask(__name__)


def to_bytes(hex_str):
    return binascii.unhexlify(hex_str.encode())


def haversine(lat1, lon1, lat2, lon2):
    R = 6371000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dl/2)**2
    return 2*R*math.atan2(math.sqrt(a), math.sqrt(1-a))


@app.route('/location', methods=['POST'])
def location():
    data = request.get_json()
    parms = seal.EncryptionParameters()
    parms.load(to_bytes(data['parms']))
    context = seal.SEALContext(parms)
    sk = seal.SecretKey()
    sk.load(context, to_bytes(data['sk']))
    decryptor = seal.Decryptor(context, sk)
    encoder = seal.BatchEncoder(context)

    ct = seal.Ciphertext()
    ct.load(context, to_bytes(data['ct']))
    plain = seal.Plaintext()
    decryptor.decrypt(ct, plain)
    decoded = encoder.decode_int64(plain)
    lat, lon = decoded[0] / 1e6, decoded[1] / 1e6

    lat_a, lon_a = 37.421998, -122.084
    if haversine(lat, lon, lat_a, lon_a) < 100:
        print('ALERT')
    else:
        print('Distance:', haversine(lat, lon, lat_a, lon_a))
    return 'OK'


if __name__ == '__main__':
    app.run()
