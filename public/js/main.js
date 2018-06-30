$(function() {
    $('.delete').on('click', function() {
        var card = $(this).parents('.card');
        if (!confirm('投稿を削除してもよろしいですか？')) {
            return;
        }
        $.post('/destroy', {
            id: card.data('id'),
        }, function() {
            card.fadeOut(500);
        });
    });
});