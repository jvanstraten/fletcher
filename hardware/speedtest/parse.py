
import sys

data = []

num_acc = 0

with open(sys.argv[1], 'r') as fi:
    with open(sys.argv[2], 'w') as fo:
        for line in fi:
            if line.startswith('simulate work columnreaderspeed_tc'):
                data.append({})
            if line.startswith('# ** Note: Minimum command length:'):
                data[-1]['cmd_len'] = int(line.split(':')[-1].strip())
            if line.startswith('# ** Note: Bus utilization:'):
                data[-1]['bus'] = int(line.split(':')[-1].split('/')[0].strip()) / 100.
            if line.startswith('# ** Note: Acc stream'):
                i = int(line.split('stream')[-1].split('utilization')[0].strip())
                if i >= num_acc:
                    num_acc = i + 1
                data[-1]['acc' + str(i)] = int(line.split(':')[-1].split('/')[0].strip()) / 100.

print('cmd_len,bus,' + ','.join(['acc' + str(i) for i in range(num_acc)]))
for d in data:
    print('%d,%.2f,' % (d['cmd_len'], d['bus']) + ','.join(['%.2f' % d['acc' + str(i)] for i in range(num_acc)]))
