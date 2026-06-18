import sys

v_list = []
with open("scan 4.obj", "r") as f:
    for line in f:
        if line.startswith("v "):
            parts = line.strip().split()
            if len(parts) >= 4:
                v_list.append((float(parts[1]), float(parts[2]), float(parts[3])))

if not v_list:
    sys.exit()

xs = [v[0] for v in v_list]
ys = [v[1] for v in v_list]
zs = [v[2] for v in v_list]

print(f"X range: {min(xs)} to {max(xs)}")
print(f"Y range: {min(ys)} to {max(ys)}")
print(f"Z range: {min(zs)} to {max(zs)}")

# Average Z of vertices that have high Y (top of head)
# We know faceCenterX is approx -0.27
# Face Y threshold is approx 0.86
top_vs = [v for v in v_list if v[1] > 0.86 and abs(v[0] - (-0.27)) < 0.2]
top_zs = [v[2] for v in top_vs]
if top_zs:
    print(f"Average Z of top head: {sum(top_zs)/len(top_zs)}")

