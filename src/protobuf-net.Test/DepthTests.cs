using ProtoBuf.Meta;
using System;
using System.IO;
using Xunit;

namespace ProtoBuf.Test
{
    public class DepthTests
    {
        // Keep this below runtime stack limits on small-stack test runners; the
        // tests are validating MaxDepth behavior, not native stack capacity.
        private const int TestMaxDepth = 128, IncreasedMaxDepth = 136;
        private readonly RuntimeTypeModel _model = RuntimeTypeModel.Create();

        [ProtoContract]
        public class RecursiveModel
        {
            [ProtoMember(1)]
            public RecursiveModel Tail { get; set; }

            public int TotalDepth()
            {
                var depth = 1;
                var tail = Tail;
                while (tail is not null)
                {
                    depth++;
                    tail = tail.Tail;
                }
                return depth;
            }
        }

        [Theory]
        // valid scenarios
        [InlineData(5, TestMaxDepth, true)]
        [InlineData(126, TestMaxDepth, true)]
        [InlineData(127, TestMaxDepth, true)]
        [InlineData(128, TestMaxDepth, true)]
        // invalid scenarios
        [InlineData(2, 1, false)] // for debugging
        [InlineData(129, TestMaxDepth, false)]
        [InlineData(130, TestMaxDepth, false)]
        // now with increased capacity
        [InlineData(129, IncreasedMaxDepth, true)]
        [InlineData(130, IncreasedMaxDepth, true)]
        public void TestSerialize(int depth, int maxDepth, bool success)
        {
            var oldDepth = _model.MaxDepth;
            try
            {
                var obj = new RecursiveModel();
                for (int i = 1; i < depth; i++)
                {
                    obj = new RecursiveModel { Tail = obj };
                }
                Assert.Equal(depth, obj.TotalDepth());
                var ms = new MemoryStream();
                _model.MaxDepth = maxDepth;

                if (success)
                {
                    _model.Serialize(ms, obj);
                    ms.Position = 0;
                    obj = _model.Deserialize<RecursiveModel>(ms);
                    Assert.Equal(depth, obj.TotalDepth());
                }
                else
                {
                    var ex = Assert.Throws<InvalidOperationException>(() => _model.Serialize(ms, obj));
                    Assert.Equal($"Maximum model depth exceeded (see TypeModel.MaxDepth): {maxDepth}", ex.Message);
                }
            }
            finally
            {
                _model.MaxDepth = oldDepth;
            }
        }

        [Theory]
        // valid scenarios
        [InlineData(5, TestMaxDepth, true)]
        [InlineData(126, TestMaxDepth, true)]
        [InlineData(127, TestMaxDepth, true)]
        [InlineData(128, TestMaxDepth, true)]
        // invalid scenarios
        [InlineData(129, TestMaxDepth, false)]
        [InlineData(130, TestMaxDepth, false)]
        // now with increased capacity
        [InlineData(129, IncreasedMaxDepth, true)]
        [InlineData(130, IncreasedMaxDepth, true)]
        public void TestDeserialize(int depth, int maxDepth, bool success)
        {
            var oldDepth = _model.MaxDepth;
            try
            {
                var obj = new RecursiveModel();
                for (int i = 1; i < depth; i++)
                {
                    obj = new RecursiveModel { Tail = obj };
                }
                Assert.Equal(depth, obj.TotalDepth());
                var ms = new MemoryStream();
                _model.MaxDepth = depth + 10;
                _model.Serialize(ms, obj);
                ms.Position = 0;
                _model.MaxDepth = maxDepth;
                if (success)
                {
                    obj = _model.Deserialize<RecursiveModel>(ms);
                    Assert.Equal(depth, obj.TotalDepth());
                }
                else
                {
                    var ex = Assert.Throws<InvalidOperationException>(() => _model.Deserialize<RecursiveModel>(ms));
                    Assert.Equal($"Maximum model depth exceeded (see TypeModel.MaxDepth): {maxDepth}", ex.Message);
                }
            }
            finally
            {
                _model.MaxDepth = oldDepth;
            }
        }
    }
}
