from flask import Flask, request, jsonify
import binascii
import math
import seal

app = Flask(__name__)

def to_hex(raw_bytes):
    return binascii.hexlify(raw_bytes).decode()

def to_bytes(hex_str):
    return binascii.unhexlify(hex_str.encode())

def create_context():
    parms = seal.EncryptionParameters(seal.scheme_type.bfv)
    parms.set_poly_modulus_degree(4096)
    parms.set_coeff_modulus(seal.CoeffModulus.BFVDefault(4096))
    parms.set_plain_modulus(seal.PlainModulus.Batching(4096, 20))
    context = seal.SEALContext(parms)
    keygen = seal.KeyGenerator(context)
    sk = keygen.secret_key()
    pk = keygen.create_public_key()
    encoder = seal.BatchEncoder(context)
    return parms, context, sk, pk, encoder

PARMS, CONTEXT, SECRET_KEY, PUBLIC_KEY, ENCODER = create_context()
PARMS_HEX = to_hex(PARMS.save())
PUBLIC_KEY_HEX = to_hex(PUBLIC_KEY.save())
PENDING_REQUESTS = {}
ACTIVE_PAIRS = set()
LATEST_LOCATIONS = {}

def pair_key(user_a, user_b):
    return tuple(sorted([user_a, user_b]))


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
    user = data.get('user')
    if not user:
        return 'Missing user', 400
    ct = seal.Ciphertext()
    ct.load(CONTEXT, to_bytes(data['ct']))
    decryptor = seal.Decryptor(CONTEXT, SECRET_KEY)
    plain = seal.Plaintext()
    decryptor.decrypt(ct, plain)
    decoded = ENCODER.decode_int64(plain)
    lat, lon = decoded[0] / 1e6, decoded[1] / 1e6

    LATEST_LOCATIONS[user] = (lat, lon)
    for pair in ACTIVE_PAIRS:
        if user in pair:
            other = pair[0] if pair[1] == user else pair[1]
            other_loc = LATEST_LOCATIONS.get(other)
            if other_loc:
                distance = haversine(lat, lon, other_loc[0], other_loc[1])
                if distance < 100:
                    print('ALERT')
                else:
                    print('Distance:', distance)
    return 'OK'

@app.route('/params', methods=['GET'])
def params():
    return jsonify({'parms': PARMS_HEX, 'pk': PUBLIC_KEY_HEX})

@app.route('/request', methods=['POST'])
def request_participant():
    data = request.get_json()
    user_from = data.get('from')
    user_to = data.get('to')
    if not user_from or not user_to:
        return 'Missing from/to', 400
    PENDING_REQUESTS.setdefault(user_to, [])
    if user_from not in PENDING_REQUESTS[user_to]:
        PENDING_REQUESTS[user_to].append(user_from)
    return 'OK'

@app.route('/requests/<user>', methods=['GET'])
def requests(user):
    pending = PENDING_REQUESTS.get(user, [])
    return jsonify({'requests': pending})

@app.route('/respond', methods=['POST'])
def respond():
    data = request.get_json()
    user_from = data.get('from')
    user_to = data.get('to')
    accepted = data.get('accepted')
    if user_from is None or user_to is None or accepted is None:
        return 'Missing response fields', 400
    pending = PENDING_REQUESTS.get(user_to, [])
    if user_from in pending:
        pending.remove(user_from)
    if accepted:
        ACTIVE_PAIRS.add(pair_key(user_from, user_to))
    return 'OK'


if __name__ == '__main__':
    app.run()
