#import "NSShape.h"
#import "Private/InterceptorPrivate.h"
#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#import <stdlib.h>
#import <string.h>

#define SHAPE_END 32767
#define SHAPE_INITIAL_Y (-32768)

typedef struct {
    short *values;
    int count;
    int capacity;
} ShortBuffer;

static short *empty_shape(NSZone *zone)
{
    short *shape = (short *)NSZoneMalloc(zone, 3 * sizeof(short));
    shape[0] = SHAPE_INITIAL_Y;
    shape[1] = 2;
    shape[2] = SHAPE_END;
    return shape;
}

static int shape_bytes(const short *shape)
{
    int position = 0;
    while (shape[position] != SHAPE_END)
        position += shape[position + 1];
    return (position + 1) * sizeof(short);
}

static short *rect_shape(NSZone *zone, const NSRect *rect)
{
    short *shape;
    float x = rect->origin.x;
    float y = rect->origin.y;
    float width = rect->size.width;
    float height = rect->size.height;

    if (width == 0 || height == 0)
        return empty_shape(zone);
    if (width < 0) {
        x += width;
        width = -width;
    }
    if (height < 0) {
        y += height;
        height = -height;
    }

    shape = (short *)NSZoneMalloc(zone, 9 * sizeof(short));
    shape[0] = SHAPE_INITIAL_Y;
    shape[1] = 2;
    shape[2] = (short)y;
    shape[3] = 4;
    shape[4] = (short)x;
    shape[5] = (short)(x + width);
    shape[6] = (short)(y + height);
    shape[7] = 2;
    shape[8] = SHAPE_END;
    return shape;
}

static int compare_short(const void *left, const void *right)
{
    short a = *(const short *)left;
    short b = *(const short *)right;
    return (a > b) - (a < b);
}

static int append_short(ShortBuffer *buffer, short value)
{
    short *grown;
    int capacity;
    if (buffer->count == buffer->capacity) {
        capacity = buffer->capacity ? buffer->capacity * 2 : 16;
        grown = (short *)realloc(buffer->values, capacity * sizeof(short));
        if (!grown) return 0;
        buffer->values = grown;
        buffer->capacity = capacity;
    }
    buffer->values[buffer->count++] = value;
    return 1;
}

static int collect_y_values(const short *shape, ShortBuffer *values)
{
    int position = 0;
    while (shape[position] != SHAPE_END) {
        if (!append_short(values, shape[position])) return 0;
        position += shape[position + 1];
    }
    return 1;
}

static void edges_at_y(const short *shape, short y, const short **edges, int *count)
{
    int position = 0;
    *edges = 0;
    *count = 0;
    while (shape[position] != SHAPE_END) {
        int length = shape[position + 1];
        if (shape[position] > y) break;
        *edges = shape + position + 2;
        *count = length - 2;
        position += length;
    }
}

static int edge_contains(const short *edges, int count, short x)
{
    int i;
    int inside = 0;
    for (i = 0; i < count; i++) {
        if (edges[i] > x) break;
        inside = !inside;
    }
    return inside;
}

static int combine_edges(const short *a, int aCount, const short *b, int bCount,
                         int operation, short *result)
{
    ShortBuffer xValues = { 0, 0, 0 };
    int i, uniqueCount, outputCount = 0, inside = 0;

    for (i = 0; i < aCount; i++)
        if (!append_short(&xValues, a[i])) goto failed;
    for (i = 0; i < bCount; i++)
        if (!append_short(&xValues, b[i])) goto failed;
    qsort(xValues.values, xValues.count, sizeof(short), compare_short);
    uniqueCount = 0;
    for (i = 0; i < xValues.count; i++)
        if (!uniqueCount || xValues.values[i] != xValues.values[uniqueCount - 1])
            xValues.values[uniqueCount++] = xValues.values[i];

    for (i = 0; i + 1 < uniqueCount; i++) {
        short left = xValues.values[i];
        short right = xValues.values[i + 1];
        int inA = edge_contains(a, aCount, left);
        int inB = edge_contains(b, bCount, left);
        int wanted = operation == 0 ? (inA || inB) :
                     operation == 1 ? (inA && inB) : (inA && !inB);
        if (wanted && !inside) result[outputCount++] = left;
        if (inside && !wanted) result[outputCount++] = left;
        inside = wanted;
        if (inside && i + 2 == uniqueCount)
            result[outputCount++] = right;
    }
    free(xValues.values);
    return outputCount;

failed:
    free(xValues.values);
    return -1;
}

static int reserve_output(NSZone *zone, short **output, int *capacity, int needed)
{
    short *grown;
    int next = *capacity;
    while (next < needed) next *= 2;
    if (next == *capacity) return 1;
    grown = (short *)NSZoneRealloc(zone, *output, next * sizeof(short));
    if (!grown) return 0;
    *output = grown;
    *capacity = next;
    return 1;
}

static short *combine_shape(NSZone *zone, const short *a, const short *b, int operation)
{
    ShortBuffer ys = { 0, 0, 0 };
    short *output;
    short *edges;
    short *previous;
    int outputCapacity = 32;
    int edgeCapacity, previousCount = 0, outputCount = 0;
    int i, uniqueCount = 0;

    if (!collect_y_values(a, &ys) || !collect_y_values(b, &ys)) {
        free(ys.values);
        return empty_shape(zone);
    }
    qsort(ys.values, ys.count, sizeof(short), compare_short);
    for (i = 0; i < ys.count; i++)
        if (!uniqueCount || ys.values[i] != ys.values[uniqueCount - 1])
            ys.values[uniqueCount++] = ys.values[i];
    ys.count = uniqueCount;

    edgeCapacity = 2 * (shape_bytes(a) + shape_bytes(b)) / sizeof(short);
    edges = (short *)malloc(edgeCapacity * sizeof(short));
    previous = (short *)malloc(edgeCapacity * sizeof(short));
    output = (short *)NSZoneMalloc(zone, outputCapacity * sizeof(short));
    if (!edges || !previous || !output) {
        free(ys.values);
        free(edges);
        free(previous);
        free(output);
        return empty_shape(zone);
    }
    output[outputCount++] = SHAPE_INITIAL_Y;
    output[outputCount++] = 2;

    for (i = 0; i < ys.count; i++) {
        const short *aEdges, *bEdges;
        int aCount, bCount, count;
        short y = ys.values[i];
        edges_at_y(a, y, &aEdges, &aCount);
        edges_at_y(b, y, &bEdges, &bCount);
        count = combine_edges(aEdges, aCount, bEdges, bCount, operation, edges);
        if (count < 0) {
            free(ys.values);
            free(edges);
            free(previous);
            free(output);
            return empty_shape(zone);
        }
        if (count != previousCount ||
            (count && memcmp(edges, previous, count * sizeof(short)))) {
            if (y != SHAPE_INITIAL_Y) {
                if (!reserve_output(zone, &output, &outputCapacity, outputCount + count + 2)) {
                    free(ys.values);
                    free(edges);
                    free(previous);
                    free(output);
                    return empty_shape(zone);
                }
                output[outputCount++] = y;
                output[outputCount++] = (short)(count + 2);
                if (count) {
                    memcpy(output + outputCount, edges, count * sizeof(short));
                    outputCount += count;
                }
            }
            if (count) memcpy(previous, edges, count * sizeof(short));
            previousCount = count;
        }
    }
    if (!reserve_output(zone, &output, &outputCapacity, outputCount + 1)) {
        free(ys.values);
        free(edges);
        free(previous);
        free(output);
        return empty_shape(zone);
    }
    output[outputCount++] = SHAPE_END;
    free(ys.values);
    free(edges);
    free(previous);
    return output;
}

static int is_equal_shape(const short *a, const short *b)
{
    while (*a == *b) {
        if (*a == SHAPE_END) return 1;
        a++;
        b++;
    }
    return 0;
}

static int is_empty_shape(const short *shape)
{
    int position = 0;
    while (shape[position] != SHAPE_END) {
        if (shape[position + 1] != 2) return 0;
        position += shape[position + 1];
    }
    return 1;
}

static void offset_shape(short *shape, int dx, int dy)
{
    int position = 2;
    while (shape[position] != SHAPE_END) {
        int count = shape[position + 1];
        int i;
        shape[position] = (short)(shape[position] + dy);
        for (i = position + 2; i < position + count; i++)
            shape[i] = (short)(shape[i] + dx);
        position += count;
    }
}

static short *union_shape(NSZone *zone, const short *a, const short *b)
{
    return combine_shape(zone, a, b, 0);
}

static short *intersect_shape(NSZone *zone, const short *a, const short *b)
{
    return combine_shape(zone, a, b, 1);
}

static short *difference_shape(NSZone *zone, const short *a, const short *b)
{
    return combine_shape(zone, a, b, 2);
}

@implementation NSShape

- init
{
    self = [super init];
    zone = [self zone];
    _impl = empty_shape(zone);
    return self;
}

- initFromRect:(NSRect)rect
{
    self = [super init];
    zone = [self zone];
    _impl = rect_shape(zone, &rect);
    return self;
}

- (void)intersectWithShape:(NSShape *)other
{
    short *oldShape = (short *)_impl;
    _impl = intersect_shape(zone, oldShape, (short *)other->_impl);
    free(oldShape);
}

- (void)unionWithShape:(NSShape *)other
{
    short *oldShape = (short *)_impl;
    _impl = union_shape(zone, oldShape, (short *)other->_impl);
    free(oldShape);
}

- (void)differenceWithShape:(NSShape *)other
{
    short *oldShape = (short *)_impl;
    _impl = difference_shape(zone, oldShape, (short *)other->_impl);
    free(oldShape);
}

- (BOOL)isEmpty
{
    return is_empty_shape((short *)_impl);
}

- (BOOL)isEqual:(NSShape *)other
{
    if (!other || [self class] != [other class]) return NO;
    return is_equal_shape((short *)_impl, (short *)other->_impl);
}

- copyWithZone:(NSZone *)aZone
{
    NSShape *copy = [NSShape allocWithZone:aZone];
    int bytes = shape_bytes((short *)_impl);
    copy->zone = aZone;
    copy->_impl = NSZoneMalloc(aZone, bytes);
    memcpy(copy->_impl, _impl, bytes);
    return copy;
}

- (void)offsetShape:(NSPoint)offset
{
    offset_shape((short *)_impl, (int)offset.x, (int)offset.y);
}

- (id<NSShapeEnumerator>)rectEnumerator
{
    return [[[_NSShapeEnumerator alloc] initForShapeImpl:(id)_impl] autorelease];
}

- (NSString *)description
{
    NSMutableString *result = [[NSMutableString allocWithZone:zone]
        initWithFormat:@"<%@: 0x%x> = (\n", [self class], (unsigned int)self];
    id<NSShapeEnumerator> enumerator = [self rectEnumerator];
    NSRect *rect;

    while ((rect = [enumerator nextRect]) != nil)
        [result appendFormat:@"\t{ x = %f; y = %f; width = %f; height = %f; },\n",
            rect->origin.x, rect->origin.y,
            rect->size.width, rect->size.height];
    [result appendString:@");\n"];
    return [result autorelease];
}

- (void)dealloc
{
    free(_impl);
    [super dealloc];
}

@end

@implementation _NSShapeEnumerator

- initForShapeImpl:(id)shape
{
    self = [super init];
    yloc = (short *)shape;
    xloc = 0;
    return self;
}

- (NSRect *)nextRect
{
    short *shape;
    int count;

    while (!xloc) {
        if (!yloc || yloc[0] == SHAPE_END) return 0;
        count = yloc[1];
        if (count == 2) {
            yloc += count;
            continue;
        }
        xloc = yloc + 2;
    }

    shape = yloc;
    r.origin.x = xloc[0];
    r.origin.y = shape[0];
    r.size.width = xloc[1] - xloc[0];
    r.size.height = shape[shape[1]] - shape[0];
    xloc += 2;
    if (xloc == shape + shape[1]) {
        xloc = 0;
        yloc = shape + shape[1];
    }
    return &r;
}

@end
